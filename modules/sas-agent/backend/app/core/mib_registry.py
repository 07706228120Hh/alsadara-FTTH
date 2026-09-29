"""
محمّل وفهرسة ملفات MIB عبر pysmi.
يقرأ ملفات .mib من knowledge/mibs/ ويبني خريطة اسم رمزي → OID رقمي.
عند غياب pysmi أو غياب الملفات يعمل بأمان بفهرس فارغ.
"""
import logging
import os
from pathlib import Path
from typing import Dict, Optional

_log = logging.getLogger(__name__)

# مسار مجلد MIBs — متوافق مع ويندوز عبر pathlib
_MIBS_DIR = Path(__file__).resolve().parent.parent / "knowledge" / "mibs"
_CACHE_DIR = _MIBS_DIR / "_mib_cache"

# علم توفّر pysmi
try:
    from pysmi.reader import FileReader
    from pysmi.searcher import StubSearcher, PyFileSearcher
    from pysmi.writer import PyFileWriter
    from pysmi.parser.smi import parserFactory
    from pysmi.codegen.pysnmp import PySnmpCodeGen
    from pysmi.compiler import MibCompiler
    HAS_PYSMI = True
except ImportError:
    HAS_PYSMI = False
    _log.info("pysmi غير مثبَّت — مسجِّل MIB يعمل بفهرس فارغ")


class MibRegistry:
    """
    فهرس رمزي→OID رقمي مبني من ملفات .mib.
    يُنشئ Cache مرة واحدة وبعدها يُجيب من الذاكرة.
    """

    def __init__(self) -> None:
        self._cache: Dict[str, str] = {}  # symbol_name -> numeric_oid
        self._loaded = False

    def _ensure_loaded(self) -> None:
        if self._loaded:
            return
        self._loaded = True
        if not HAS_PYSMI:
            return
        mib_files = list(_MIBS_DIR.glob("*.mib"))
        if not mib_files:
            _log.debug("لم تُعثر على ملفات .mib في %s — الفهرس فارغ", _MIBS_DIR)
            return
        try:
            _CACHE_DIR.mkdir(parents=True, exist_ok=True)
            self._compile_and_load(mib_files)
        except Exception as exc:
            _log.warning("فشل تحميل ملفات MIB (غير مميت): %s", exc)

    def _compile_and_load(self, mib_files: list) -> None:
        """يُترجم ملفات .mib إلى Python ويستخرج خريطة الرموز."""
        mib_names = [f.stem for f in mib_files]
        compiler = MibCompiler(
            parserFactory()(),
            PySnmpCodeGen(),
            PyFileWriter(str(_CACHE_DIR)),
        )
        compiler.add_sources(FileReader(str(_MIBS_DIR)))
        compiler.add_searchers(StubSearcher(*mib_names))
        compiler.add_searchers(PyFileSearcher(str(_CACHE_DIR)))
        try:
            results = compiler.compile(*mib_names)
            _log.debug("ترجمة MIB: %s", results)
        except Exception as exc:
            _log.warning("خطأ في ترجمة MIB: %s", exc)

        # استخراج OIDs من ملفات Python المُولَّدة
        self._extract_oids_from_cache()

    def _extract_oids_from_cache(self) -> None:
        """يقرأ ملفات Python المُولَّدة في _mib_cache ويستخرج OIDs."""
        import importlib.util
        import sys

        for py_file in _CACHE_DIR.glob("*.py"):
            try:
                mod_name = f"_mib_cache_{py_file.stem}"
                spec = importlib.util.spec_from_file_location(
                    mod_name, str(py_file)
                )
                if spec is None or spec.loader is None:
                    continue
                mod = importlib.util.module_from_spec(spec)
                sys.modules[mod_name] = mod
                spec.loader.exec_module(mod)  # type: ignore[attr-defined]
                # PySnmpCodeGen يُولّد MibIdentifier / ObjectType / NotificationType إلخ
                mib_data = getattr(mod, "MIBObjects", None) or {}
                if isinstance(mib_data, dict):
                    for sym, obj in mib_data.items():
                        try:
                            oid = self._extract_oid(obj)
                            if oid:
                                self._cache[sym] = oid
                        except Exception:
                            pass
                # بديل: iterable على مستوى الموديل
                for attr in dir(mod):
                    if attr.startswith("_"):
                        continue
                    try:
                        obj = getattr(mod, attr)
                        oid = self._extract_oid(obj)
                        if oid and attr not in self._cache:
                            self._cache[attr] = oid
                    except Exception:
                        pass
            except Exception as exc:
                _log.debug("فشل قراءة %s: %s", py_file.name, exc)

        _log.info("فهرس MIB: %d رمز محلول", len(self._cache))

    @staticmethod
    def _extract_oid(obj) -> Optional[str]:
        """يحاول استخراج OID رقمي من كائن pysnmp المُولَّد."""
        try:
            # كائنات pysnmp المُولَّدة تحوي getName() أو .name
            name = None
            if hasattr(obj, "getName"):
                name = obj.getName()
            elif hasattr(obj, "name"):
                name = obj.name
            if name and hasattr(name, "__iter__") and not isinstance(name, str):
                # tuple of ints → OID رقمي
                return ".".join(str(x) for x in name)
        except Exception:
            pass
        return None

    def resolve(self, name: str) -> Optional[str]:
        """
        يُرجع OID رقمياً من اسم رمزي مثل 'hwGponOntOpticalDdmRxPower'.
        يُرجع None إن لم يُعثر عليه.
        """
        self._ensure_loaded()
        return self._cache.get(name)

    def __len__(self) -> int:
        self._ensure_loaded()
        return len(self._cache)

    def symbols(self) -> list:
        """قائمة بكل الرموز المحلولة."""
        self._ensure_loaded()
        return list(self._cache.keys())


# مثيل عام — يُستورَد من بقية الوحدات
registry = MibRegistry()
