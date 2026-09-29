"""نقاط نهاية التزويد"""
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session
from ..database import get_session
from ..models import OLTDevice, AuditLog
from ..schemas import FTTHProvisionRequest, MDUSIPProvisionRequest
from ..services import provisioning
from ..core.auth import require_role

router = APIRouter(prefix="/api/provision", tags=["provisioning"],
                   dependencies=[Depends(require_role("operator"))])


def _run_plan(device, plan, req, db: Session):
    """معاينة (dry_run) أو تنفيذ خطة مع تسجيلها في Audit log."""
    if req.dry_run:
        return {
            "dry_run": True,
            "steps": [{"title": s["title"], "commands": s["commands"]} for s in plan.steps],
            "note": "راجع الأوامر ثم أعد الطلب بـ dry_run=false للتنفيذ.",
        }

    def log_fn(olt_id, command, kind, success, output):
        db.add(AuditLog(olt_id=olt_id, command=command, kind=kind,
                        success=success, result=output[:1000]))

    result = provisioning.execute_plan(device, plan, log_fn=log_fn)
    db.commit()
    return result


@router.post("/{device_id}/ftth")
def provision_ftth(device_id: int, req: FTTHProvisionRequest,
                   db: Session = Depends(get_session)):
    """
    تفعيل مشترك FTTH. service_type: hsi (إنترنت) أو iptv (multicast).
    مع dry_run=true يُرجع الأوامر فقط للمراجعة قبل التنفيذ.
    """
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")

    st = (req.service_type or "hsi").lower()
    if st == "iptv":
        plan = provisioning.build_iptv_plan(
            fsp=req.fsp, ont_id=req.ont_id, sn=req.sn, mvlan=req.mvlan,
            uplink_fsp=req.uplink_fsp, stb_eth=req.stb_eth,
            preprovision=req.preprovision,
            igmp_version=req.igmp_version, igmp_mode=req.igmp_mode,
        )
    elif st == "fttb":
        plan = provisioning.build_fttb_plan(
            fsp=req.fsp, ont_id=req.ont_id, sn=req.sn,
            svlan=req.svlan, cvlan=req.cvlan,
            uplink_fsp=req.uplink_fsp, preprovision=req.preprovision,
            eth_port=req.eth_port, car_index=req.car_index,
            car_cir=req.car_cir, car_pir=req.car_pir,
        )
    elif st == "xdsl":
        plan = provisioning.build_xdsl_plan(
            dsl_type=req.dsl_type, fsp=req.fsp, ont_id=req.ont_id, sn=req.sn,
            svlan=req.svlan, cvlan=req.cvlan,
            uplink_fsp=req.uplink_fsp, preprovision=req.preprovision,
            vpi=req.vpi, vci=req.vci, car_index=req.car_index,
            car_cir=req.car_cir, car_pir=req.car_pir,
        )
    elif st == "hsi":
        plan = provisioning.build_ftth_plan(
            fsp=req.fsp, ont_id=req.ont_id, sn=req.sn,
            svlan=req.svlan, cvlan=req.cvlan,
            uplink_fsp=req.uplink_fsp, preprovision=req.preprovision,
            dba_max=req.dba_max, profile_name=req.profile_name,
            car_index=req.car_index, car_cir=req.car_cir, car_pir=req.car_pir,
        )
    else:
        raise HTTPException(400, f"نوع خدمة غير مدعوم: {st} (المتاح: hsi, iptv, fttb, xdsl)")

    return _run_plan(device, plan, req, db)


@router.post("/{device_id}/voip")
def provision_mdu_sip(device_id: int, req: MDUSIPProvisionRequest,
                      db: Session = Depends(get_session)):
    """
    تفعيل خدمة الصوت SIP على MDU/MxU (HCIP-Access Lab §3).
    تنبيه: `protocol support sip` يتطلب save ثم reboot لتفعيله فعلياً.
    """
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")

    users = [{"fsp": u.fsp, "telno": u.telno} for u in (req.users or [])]
    plan = provisioning.build_mdu_sip_plan(
        voice_vlan=req.voice_vlan, uplink_fsp=req.uplink_fsp,
        mdu_ip=req.mdu_ip, mask_bits=req.mask_bits, media_ip=req.media_ip,
        gateway=req.gateway, softswitch_net=req.softswitch_net,
        softswitch_mask_bits=req.softswitch_mask_bits,
        softswitch_nexthop=req.softswitch_nexthop, proxy_ip=req.proxy_ip,
        mgid=req.mgid, users=users,
    )
    return _run_plan(device, plan, req, db)
