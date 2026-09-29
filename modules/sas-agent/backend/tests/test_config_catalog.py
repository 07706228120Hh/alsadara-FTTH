"""اختبارات كتالوج التهيئة — يبني كل إجراء ويؤكد توليد أوامر صحيحة + مسار apply."""
from app.services import config_catalog as cc


def _defaults(proc):
    """يجمع القيم الافتراضية لحقول إجراء (مع قيم بديلة للحقول الإلزامية بلا افتراضي)."""
    params = {}
    for f in proc["fields"]:
        if "default" in f:
            params[f["name"]] = f["default"]
        elif f["type"] == "int":
            params[f["name"]] = 1
        elif f["type"] == "bool":
            params[f["name"]] = False
        else:
            params[f["name"]] = "TEST"
    return params


def test_catalog_has_categories_and_procedures():
    assert len(cc.CATALOG) >= 6
    ids = cc.procedure_ids()
    # كل إجراء في الكتالوج له بانٍ مسجّل
    for cat in cc.CATALOG:
        for proc in cat["procedures"]:
            assert proc["id"] in ids, proc["id"]
            assert "fields" in proc, proc["id"]
            assert proc["title_ar"] and proc["wiring_ar"]


def test_every_procedure_builds_nonempty_commands():
    for cat in cc.CATALOG:
        for proc in cat["procedures"]:
            steps = cc.build(proc["id"], _defaults(proc))
            assert steps, proc["id"]
            for s in steps:
                assert s["commands"], f"{proc['id']} -> {s['title']}"
                assert s["kind"] in ("read", "write", "dangerous")


def test_hsi_procedure_matches_reference():
    steps = cc.build("ftth_hsi", {
        "fsp": "0/5/0", "ont_id": 3, "sn": "48575443E1F0A409",
        "svlan": 2000, "cvlan": 35, "uplink_fsp": "0/19/0",
        "dba_max": 4096, "profile_name": "hsi", "car_index": 10,
    })
    flat = [c for s in steps for c in s["commands"]]
    assert any("service-port" in c for c in flat)
    assert flat[-1] == "save"


def test_dangerous_ont_delete_flagged():
    steps = cc.build("ont_lifecycle",
                     {"fsp": "0/5/0", "ont_id": 2, "action": "delete"})
    flat = [c for s in steps for c in s["commands"]]
    assert any(c.startswith("ont delete") for c in flat)
    # الأمر الخطر يُصنّف dangerous في خطوته
    assert any(s["kind"] == "dangerous" for s in steps)


def test_unknown_procedure_raises():
    import pytest
    with pytest.raises(KeyError):
        cc.build("does_not_exist", {})


def test_api_catalog_and_apply(client):
    # الكتالوج متاح
    r = client.get("/api/config/catalog")
    assert r.status_code == 200
    assert len(r.json()["catalog"]) >= 6

    # build (dry-run) لإجراء VLAN
    r = client.post("/api/config/1/build",
                    json={"procedure": "create_vlan", "params": {"vlan": 2500}})
    assert r.status_code == 200
    body = r.json()
    assert body["dry_run"] is True
    assert any("vlan 2500" in c for s in body["steps"] for c in s["commands"])

    # apply ينفّذ على المحاكي
    r = client.post("/api/config/1/apply",
                    json={"procedure": "create_vlan", "params": {"vlan": 2500}})
    assert r.status_code == 200
    assert r.json()["ok"] is True

    # إجراء غير معروف → 400
    r = client.post("/api/config/1/build", json={"procedure": "nope", "params": {}})
    assert r.status_code == 400
