"""WebSocket للتحديثات الحية (المراقبة)"""
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from ..services.monitoring import hub
from ..core.auth import ws_authorized

router = APIRouter()


@router.websocket("/ws/monitor")
async def monitor_ws(ws: WebSocket, token: str = ""):
    # مصادقة عبر query param: ws://host/ws/monitor?token=<API_TOKEN>
    if not ws_authorized(token):
        await ws.close(code=1008)   # 1008 = Policy Violation
        return
    await ws.accept()
    hub.subscribe(ws)
    try:
        await ws.send_json({"type": "hello", "message": "متصل بمراقبة OLT الحية"})
        while True:
            await ws.receive_text()   # نبقي الاتصال حياً
    except WebSocketDisconnect:
        hub.unsubscribe(ws)
    except Exception:
        hub.unsubscribe(ws)
