"""اختبارات مزامنة SAS: كشف الدمج + نقاط الوكلاء/التدقيق/الدمج."""
from uuid import uuid4

from fastapi.testclient import TestClient
from sqlmodel import Session, delete

from app.main import app
from app.database import engine
from app.models import Company, CompanySnapshot, Agent, MergeFinding
from app.services.sas_sync import compute_merge_findings

client = TestClient(app)


def test_merge_load_balancing_and_bonding_and_shared():
    sessions = [
        {"username": "ali", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.5", "callingstationid": "AA"},
        {"username": "ali", "nasipaddress": "10.0.0.2", "framedipaddress": "1.1.1.6", "callingstationid": "AA"},
        {"username": "sara", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.7", "callingstationid": "BB"},
        {"username": "sara", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.8", "callingstationid": "BB"},
        {"username": "u1", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.9", "callingstationid": "CC"},
        {"username": "u2", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.2.0", "callingstationid": "CC"},
    ]
    kinds = {f.kind for f in compute_merge_findings(1, sessions)}
    assert "LOAD_BALANCING_SUSPECTED" in kinds
    assert "BONDING_SUSPECTED" in kinds
    assert "SHARED_LINE_SUSPECTED" in kinds


def test_merge_clean_sessions_no_findings():
    sessions = [
        {"username": "a", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.1", "callingstationid": "M1"},
        {"username": "b", "nasipaddress": "10.0.0.1", "framedipaddress": "1.1.1.2", "callingstationid": "M2"},
    ]
    assert compute_merge_findings(1, sessions) == []


def test_agents_audit_merge_endpoints():
    """يتحقّق من عقد النقاط بمعزل عن حالة القاعدة المشتركة (عضوية + صحّة التصفية + الثوابت)."""
    code = "au_" + uuid4().hex[:6]
    with Session(engine) as db:
        co = Company(name="ش. تدقيق", code=code, enabled=True)
        db.add(co); db.commit(); db.refresh(co)
        # نظافة دفاعية ضد إعادة استخدام SQLite للـ rowid (أيتام من اختبارات سابقة)
        db.exec(delete(Agent).where(Agent.company_id == co.id))
        db.exec(delete(MergeFinding).where(MergeFinding.company_id == co.id))
        db.exec(delete(CompanySnapshot).where(CompanySnapshot.company_id == co.id))
        db.commit()
        db.add(CompanySnapshot(company_id=co.id, total=100, active=90, managers=2))
        db.add(Agent(company_id=co.id, manager_id=1, username="m1", users_count=40))
        db.add(Agent(company_id=co.id, manager_id=2, username="m2", users_count=35))
        db.add(MergeFinding(company_id=co.id, username="x", kind="BONDING_SUSPECTED", detail="d"))
        db.commit()
        cid = co.id

    # الوكلاء: التصفية صحيحة (كل صف يخصّ الشركة) والعضوية موجودة
    ag = client.get("/api/companies/agents/all", params={"company_id": cid}).json()
    assert all(a["company_id"] == cid for a in ag["agents"])       # صحّة التصفية
    usernames = {a["username"] for a in ag["agents"]}
    assert {"m1", "m2"} <= usernames
    assert ag["count"] == 2

    # التدقيق: ثابت الفرق + دلالة الحالة (بمعزل عن باقي الشركات)
    audit = client.get("/api/companies/audit").json()["audit"]
    row = next(r for r in audit if r["code"] == code)
    assert row["agent_reported_sum"] == 75 and row["company_total"] == 100
    assert row["difference"] == row["company_total"] - row["agent_reported_sum"]
    assert row["difference"] == 25 and row["status"] == "unattributed_subscribers"

    # كشف الدمج: التصفية صحيحة والعضوية موجودة
    mf = client.get("/api/companies/merge-findings", params={"company_id": cid}).json()
    assert all(f["company_id"] == cid for f in mf["findings"])
    assert mf["count"] == 1 and mf["by_kind"].get("BONDING_SUSPECTED") == 1

    client.delete(f"/api/companies/{cid}")   # تنظيف


def test_company_get_by_id_not_shadowed_by_static_routes():
    # يتأكد أن /audit و/merge-findings لا يبتلعهما مسار /{company_id}
    assert client.get("/api/companies/audit").status_code == 200
    assert client.get("/api/companies/merge-findings").status_code == 200
