"""نقاط نهاية إدارة الأجهزة وتنفيذ الأوامر"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..models import OLTDevice, AuditLog, ConfigSnapshot
from ..schemas import DeviceCreate, DeviceOut, CommandRequest
from ..core.security import encrypt
from ..core.olt_connection import manager
from ..core.snmp_client import snmp_manager
from ..core import command_library as cl
from ..core.auth import require_role

router = APIRouter(prefix="/api/devices", tags=["devices"])

_operator = [Depends(require_role("operator"))]
_admin = [Depends(require_role("admin"))]


@router.get("", response_model=list[DeviceOut])
def list_devices(db: Session = Depends(get_session)):
    return db.exec(select(OLTDevice)).all()


@router.post("", response_model=DeviceOut, dependencies=_admin)
def add_device(payload: DeviceCreate, db: Session = Depends(get_session)):
    # تشفير مفاتيح SNMP فقط إن لم تكن فارغة
    auth_key_enc = encrypt(payload.snmp_auth_key) if payload.snmp_auth_key else ""
    priv_key_enc = encrypt(payload.snmp_priv_key) if payload.snmp_priv_key else ""
    device = OLTDevice(
        name=payload.name, host=payload.host, port=payload.port,
        protocol=payload.protocol, username=payload.username,
        password_enc=encrypt(payload.password), model=payload.model,
        # حقول SNMPv3
        snmp_enabled=payload.snmp_enabled,
        snmp_port=payload.snmp_port,
        snmp_user=payload.snmp_user,
        snmp_auth_proto=payload.snmp_auth_proto,
        snmp_auth_key_enc=auth_key_enc,
        snmp_priv_proto=payload.snmp_priv_proto,
        snmp_priv_key_enc=priv_key_enc,
        snmp_context=payload.snmp_context,
        snmp_engine_id=payload.snmp_engine_id,
        adapter_profile=payload.adapter_profile,
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    return device


@router.delete("/{device_id}", dependencies=_admin)
def delete_device(device_id: int, db: Session = Depends(get_session)):
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    manager.drop(device_id)         # جلسة CLI (Netmiko)
    snmp_manager.drop(device_id)    # جلسة SNMPv3
    db.delete(device)
    db.commit()
    return {"ok": True}


@router.post("/{device_id}/command", dependencies=_operator)
def run_command(device_id: int, req: CommandRequest, confirm: bool = False,
                db: Session = Depends(get_session)):
    """تنفيذ أمر مباشر — أوامر الخطر تحتاج confirm=true"""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    kind = cl.classify(req.command)
    if kind == "dangerous" and not confirm:
        raise HTTPException(400, {"error": "أمر خطر — أعد الطلب مع confirm=true", "kind": kind})
    sess = manager.get(device)
    if kind == "read":
        output = sess.run(req.command)
    else:
        output = sess.run_config([req.command])
    db.add(AuditLog(olt_id=device_id, command=req.command, result=output[:2000],
                    kind=kind, success=True))
    db.commit()
    return {"command": req.command, "kind": kind, "output": output}


@router.get("/{device_id}/audit")
def get_audit(device_id: int, limit: int = 100, db: Session = Depends(get_session)):
    stmt = select(AuditLog).where(AuditLog.olt_id == device_id).order_by(
        AuditLog.id.desc()).limit(limit)
    return db.exec(stmt).all()


# ---------------------------------------------------------------------------
# نسخ احتياطي ومقارنة الإعدادات
# ---------------------------------------------------------------------------

@router.post("/{device_id}/snapshot", dependencies=_operator)
def create_snapshot(device_id: int, note: str = "", db: Session = Depends(get_session)):
    """التقاط نسخة من الإعدادات الحالية (display current-configuration) وتخزينها."""
    device = db.get(OLTDevice, device_id)
    if not device:
        raise HTTPException(404, "الجهاز غير موجود")
    sess = manager.get(device)
    output = sess.run(cl.DISPLAY["current_config"]())
    snap = ConfigSnapshot(olt_id=device_id, content=output, note=note)
    db.add(snap)
    db.add(AuditLog(olt_id=device_id, command="snapshot create",
                    result=f"snapshot id={snap.id}", kind="write", success=True))
    db.commit()
    db.refresh(snap)
    return {"id": snap.id, "created_at": snap.created_at, "note": snap.note}


@router.get("/{device_id}/snapshots")
def list_snapshots(device_id: int, limit: int = 100, db: Session = Depends(get_session)):
    """قائمة النسخ الاحتياطية المخزّنة لجهاز معيّن."""
    stmt = select(ConfigSnapshot).where(
        ConfigSnapshot.olt_id == device_id).order_by(
        ConfigSnapshot.created_at.desc()).limit(limit)
    rows = db.exec(stmt).all()
    return [{"id": r.id, "created_at": r.created_at, "note": r.note} for r in rows]


@router.get("/{device_id}/snapshot/{snapshot_id}")
def get_snapshot(device_id: int, snapshot_id: int, db: Session = Depends(get_session)):
    """محتوى نسخة احتياطية كاملة."""
    snap = db.get(ConfigSnapshot, snapshot_id)
    if not snap or snap.olt_id != device_id:
        raise HTTPException(404, "النسخة غير موجودة")
    return {"id": snap.id, "created_at": snap.created_at, "note": snap.note,
            "content": snap.content}


@router.post("/{device_id}/snapshot/{snapshot_id}/compare", dependencies=_operator)
def compare_snapshot(device_id: int, snapshot_id: int,
                     other_id: Optional[int] = None,
                     db: Session = Depends(get_session)):
    """
    مقارنة نسخة بالإعدادات الحالية (other_id=null) أو بنسخة أخرى.
    يُرجع diff بنمط unified (أو simple list من الأسطر المختلفة).
    """
    import difflib
    snap = db.get(ConfigSnapshot, snapshot_id)
    if not snap or snap.olt_id != device_id:
        raise HTTPException(404, "النسخة غير موجودة")

    if other_id is None:
        device = db.get(OLTDevice, device_id)
        if not device:
            raise HTTPException(404, "الجهاز غير موجود")
        sess = manager.get(device)
        current = sess.run(cl.DISPLAY["current_config"]())
        label_a = "الحالية"
    else:
        other = db.get(ConfigSnapshot, other_id)
        if not other or other.olt_id != device_id:
            raise HTTPException(404, "النسخة الثانية غير موجودة")
        current = other.content
        label_a = f"نسخة #{other_id}"

    a_lines = snap.content.splitlines()
    b_lines = current.splitlines()
    diff = list(difflib.unified_diff(
        a_lines, b_lines,
        fromfile=f"نسخة #{snapshot_id}",
        tofile=label_a,
        lineterm=""))
    return {
        "snapshot_id": snapshot_id,
        "other_id": other_id,
        "diff": diff,
        "added": [l[1:] for l in diff if l.startswith("+") and not l.startswith("+++")],
        "removed": [l[1:] for l in diff if l.startswith("-") and not l.startswith("---")],
    }
