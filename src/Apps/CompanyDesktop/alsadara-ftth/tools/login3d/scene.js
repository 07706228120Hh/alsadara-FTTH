// مدينة الصدارة ثلاثية الأبعاد — Three.js (يُحزَّم بـ esbuild في ملف HTML واحد يعمل بلا إنترنت)
// برج الصدارة الملتف في المركز + مدينة ليلية ممتدة تذوب في الضباب + شبكة ألياف تتدفق فيها نبضات
// + سيارات وأضواء شوارع + مبانٍ تفاعلية يمكن الدخول إليها.
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

const CFG = Object.assign({ shiftX: 0, quality: 'high', interactive: true, logo: '' }, window.SD_CFG || {});
const LOW = CFG.quality === 'low';
const NAVY = 0x0B1B3F, GOLD = 0xC9A44C, GOLD_L = 0xE6C67A, CYAN = 0x4DD0E1;

// ───────────────────────── المشهد والمحرّك ─────────────────────────
const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: !LOW, powerPreference: 'high-performance', alpha: false });
let pixelRatio = Math.min(window.devicePixelRatio || 1, LOW ? 1 : 1.75);
renderer.setPixelRatio(pixelRatio);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.4;
renderer.shadowMap.enabled = !LOW;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
scene.fog = new THREE.FogExp2(0x1A2C63, LOW ? 0.0058 : 0.0048);

const camera = new THREE.PerspectiveCamera(42, 1, 0.5, 900);
camera.position.set(140, 105, 175);

const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(renderer), 0.04).texture;

// السماء: تدرّج ليلي + نجوم
{
  const g = new THREE.SphereGeometry(600, 32, 16);
  const m = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color(0x050A1E) }, mid: { value: new THREE.Color(0x13245A) }, hor: { value: new THREE.Color(0x1A2C63) } },
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.0);} ',
    fragmentShader: 'uniform vec3 top; uniform vec3 mid; uniform vec3 hor; varying vec3 vP; void main(){ float h = vP.y; vec3 glow = vec3(0.10,0.13,0.26)*smoothstep(0.0,0.04,h)*exp(-max(h,0.0)*9.0); vec3 c = (h>0.0 ? mix(mix(hor,mid,smoothstep(0.0,0.22,h)), top, smoothstep(0.22,0.85,h)) : hor) + glow; gl_FragColor = vec4(c,1.0);\n #include <tonemapping_fragment>\n #include <colorspace_fragment>\n} ',
  });
  scene.add(new THREE.Mesh(g, m));
  const n = LOW ? 500 : 1400, pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const t = Math.random() * Math.PI * 2, p = Math.random() * 1.2 + 0.25;
    pos[i * 3] = Math.cos(t) * Math.cos(p) * 560; pos[i * 3 + 1] = Math.sin(p) * 560; pos[i * 3 + 2] = Math.sin(t) * Math.cos(p) * 560;
  }
  const sg = new THREE.BufferGeometry(); sg.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  scene.add(new THREE.Points(sg, new THREE.PointsMaterial({ color: 0xBFD3FF, size: 1.3, sizeAttenuation: false, fog: false, transparent: true, opacity: 0.8 })));
}

// الإضاءة
scene.add(new THREE.HemisphereLight(0x8FA8FF, 0x1A2238, 1.15));
const moon = new THREE.DirectionalLight(0xC9D6FF, 1.9);
moon.position.set(-80, 140, 60);
moon.castShadow = !LOW;
moon.shadow.mapSize.set(2048, 2048);
Object.assign(moon.shadow.camera, { left: -110, right: 110, top: 110, bottom: -110, near: 10, far: 400 });
moon.shadow.bias = -0.0004;
scene.add(moon);
const warm = new THREE.DirectionalLight(0xFFC98A, 0.8); warm.position.set(120, 40, -80); scene.add(warm);

// ───────────────────────── قوام مولَّدة ─────────────────────────
function windowTexture(cols, rows, seed, litColors, litRatio) {
  const c = document.createElement('canvas'); c.width = 256; c.height = 512;
  const x = c.getContext('2d');
  const gr = x.createLinearGradient(0, 0, 256, 0); gr.addColorStop(0, '#0a1124'); gr.addColorStop(0.5, '#0e1730'); gr.addColorStop(1, '#0a1124');
  x.fillStyle = gr; x.fillRect(0, 0, 256, 512);
  let s = seed; const rnd = () => (s = (s * 9301 + 49297) % 233280) / 233280;
  const cw = 256 / cols, rh = 512 / rows;
  for (let r = 0; r < rows; r++) {
   const floorDark = rnd() < 0.18; // طوابق مطفأة بالكامل لواقعية أكثر
   for (let k = 0; k < cols; k++) {
    const lit = !floorDark && rnd() < litRatio;
    x.fillStyle = lit ? litColors[Math.floor(rnd() * litColors.length)] : (rnd() < 0.5 ? '#141d38' : '#18223f');
    x.globalAlpha = lit ? 0.75 + rnd() * 0.25 : 1;
    x.fillRect(k * cw + cw * 0.12, r * rh + rh * 0.2, cw * 0.76, rh * 0.6);
   }
  }
  // خطوط أعمدة الواجهة
  x.fillStyle = 'rgba(120,140,190,.10)'; for (let k = 0; k <= cols; k++) x.fillRect(k * cw - 1, 0, 2, 512);
  x.globalAlpha = 1;
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = 4; t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}
const WARM = ['#ffd9a0', '#ffe7bf', '#ffcf86', '#fff1d6'], COOL = ['#bfe3ff', '#d7ecff', '#9fd4ff'];

function groundTexture() {
  const c = document.createElement('canvas'); c.width = c.height = 512; const x = c.getContext('2d');
  x.fillStyle = '#0b1124'; x.fillRect(0, 0, 512, 512);           // أسفلت
  const S = 512 * (6 / 20);                                        // عرض الشارع
  x.fillStyle = '#101a33'; x.fillRect(S, S, 512 - S, 512 - S);     // رصيف/كتلة
  x.fillStyle = '#0d152b'; x.fillRect(S + 12, S + 12, 512 - S - 24, 512 - S - 24);
  x.strokeStyle = 'rgba(255,214,130,.9)'; x.lineWidth = 4; x.setLineDash([22, 22]);
  x.beginPath(); x.moveTo(S / 2, 0); x.lineTo(S / 2, 512); x.moveTo(0, S / 2); x.lineTo(512, S / 2); x.stroke();
  x.setLineDash([]); x.strokeStyle = 'rgba(160,180,230,.18)'; x.lineWidth = 2;
  x.strokeRect(S + 1, S + 1, 512 - S - 2, 512 - S - 2);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  return t;
}

// ───────────────────────── الأرض والمدينة الممتدة ─────────────────────────
const BLOCK = 20, N = LOW ? 7 : 10;
{
  const tex = groundTexture(); const size = 1120; // أرض دائرية واسعة تذوب في الضباب — بلا حواف مرئية
  tex.repeat.set(size / BLOCK, size / BLOCK); tex.offset.set(0.5, 0.5); // محاذاة الشوارع مع شبكة المباني
  const ground = new THREE.Mesh(new THREE.CircleGeometry(size / 2, 96),
    new THREE.MeshStandardMaterial({ map: tex, color: 0x9aa6c8, roughness: 0.45, metalness: 0.15, envMapIntensity: 0.18, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 0.35 }));
  ground.rotation.x = -Math.PI / 2; ground.position.set(0, 0, 0); ground.receiveShadow = true;
  scene.add(ground);
}

// مواد المباني البعيدة (حسب فئة الارتفاع)
const roofMat = new THREE.MeshStandardMaterial({ color: 0x1d2747, roughness: 0.8, metalness: 0.1, envMapIntensity: 0.15 });
const classes = [6, 10, 16, 26, 40].map((h, i) => {
  const floors = Math.round(h / 3.2);
  const tex = windowTexture(12, 32, 11 + i * 7, i % 2 ? COOL : WARM, 0.55);
  tex.repeat.set(1, floors / 32);
  const side = new THREE.MeshStandardMaterial({ color: 0x2a3760, map: tex, emissive: 0xffffff, emissiveMap: tex, emissiveIntensity: 1.1, roughness: 0.4, metalness: 0.3, envMapIntensity: 0.3 });
  return { h, mats: [side, side, roofMat, roofMat, side, side], list: [] };
});

const HERO_SLOTS = new Map(); // مواقع محجوزة للمباني التفاعلية والبرج
function reserve(bx, bz) { HERO_SLOTS.set(bx + ',' + bz, true); }
reserve(0, 0);
let seed = 7; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;

const heroDefs = [
  { id: 'tower', bx: 1, bz: -1, kind: 'glass', name: 'برج «الياسمين» السكني', type: 'سكني متعدد الطوابق', floors: 18, subs: 64, online: 61, rx: '-19.4', fat: 'FAT-07' },
  { id: 'office', bx: -1, bz: -1, kind: 'office', name: 'مجمّع الأعمال الرقمي', type: 'مكاتب شركات', floors: 12, subs: 38, online: 38, rx: '-16.2', fat: 'FAT-11' },
  { id: 'mall', bx: -1, bz: 1, kind: 'mall', name: 'مول الصدارة التجاري', type: 'مركز تسوّق', floors: 3, subs: 45, online: 43, rx: '-18.1', fat: 'FAT-05' },
  { id: 'villa', bx: 1, bz: 1, kind: 'villa', name: 'فيلا «النخيل»', type: 'منزل مستقل', floors: 2, subs: 1, online: 1, rx: '-17.8', fat: 'FAT-03' },
  { id: 'apts', bx: 2, bz: 0, kind: 'apts', name: 'عمارات «الرافدين»', type: 'سكني', floors: 9, subs: 36, online: 33, rx: '-20.3', fat: 'FAT-04' },
  { id: 'school', bx: -2, bz: 0, kind: 'school', name: 'مدرسة المستقبل', type: 'مؤسسة تعليمية', floors: 3, subs: 6, online: 6, rx: '-18.9', fat: 'FAT-09' },
  { id: 'hospital', bx: 0, bz: 2, kind: 'hospital', name: 'مستشفى الشفاء', type: 'مؤسسة صحية', floors: 6, subs: 22, online: 22, rx: '-17.1', fat: 'FAT-12' },
  { id: 'house', bx: 0, bz: -2, kind: 'house', name: 'منزل «الريان»', type: 'منزل عائلي', floors: 2, subs: 1, online: 0, rx: '—', fat: 'FAT-02' },
];
heroDefs.forEach(d => reserve(d.bx, d.bz));

// كتل المدينة: 1–4 مبانٍ في كل كتلة، أعلى قرب المركز
for (let bx = -N; bx <= N; bx++) for (let bz = -N; bz <= N; bz++) {
  if (HERO_SLOTS.has(bx + ',' + bz)) continue;
  const d = Math.hypot(bx, bz);
  const cx = bx * BLOCK + 3, cz = bz * BLOCK + 3;      // مركز الكتلة (الشارع على حافتها)
  const split = rnd() < 0.55 ? 2 : 1;
  const cell = 13 / split;
  for (let i = 0; i < split; i++) for (let k = 0; k < split; k++) {
    if (rnd() < 0.08) continue;
    let ci = Math.min(4, Math.floor(rnd() * 2.2 + Math.max(0, 3.4 - d * 0.55)));
    if (d > 4) ci = Math.min(ci, 2);
    if (d > 7) ci = Math.min(ci, 1);
    const w = cell * (0.62 + rnd() * 0.3), dd = cell * (0.62 + rnd() * 0.3);
    const h = classes[ci].h * (0.8 + rnd() * 0.4);
    classes[ci].list.push({ x: cx - 6.5 + cell * (i + 0.5), z: cz - 6.5 + cell * (k + 0.5), w, d: dd, h });
  }
}
const farBox = new THREE.BoxGeometry(1, 1, 1); farBox.translate(0, 0.5, 0);
const dummy = new THREE.Object3D();
const blinkers = [];
classes.forEach(c => {
  if (!c.list.length) return;
  const im = new THREE.InstancedMesh(farBox, c.mats, c.list.length);
  c.list.forEach((b, i) => {
    dummy.position.set(b.x, 0, b.z); dummy.scale.set(b.w, b.h, b.d); dummy.rotation.set(0, 0, 0); dummy.updateMatrix();
    im.setMatrixAt(i, dummy.matrix);
    if (b.h > 30 && blinkers.length < 30) blinkers.push(new THREE.Vector3(b.x, b.h + 1.2, b.z));
  });
  im.castShadow = !LOW; im.receiveShadow = true;
  scene.add(im);
});
// أضواء تحذير حمراء فوق الأبراج العالية
const blinkMat = new THREE.MeshBasicMaterial({ color: 0xff3344 });
const blinkMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(0.28, 8, 6), blinkMat, Math.max(1, blinkers.length));
blinkers.forEach((p, i) => { dummy.position.copy(p); dummy.scale.setScalar(1); dummy.updateMatrix(); blinkMesh.setMatrixAt(i, dummy.matrix); });
blinkMesh.count = blinkers.length; scene.add(blinkMesh);

// أعمدة إنارة الشوارع (نقاط دافئة)
{
  const pts = [];
  const R = LOW ? 5 : 8;
  for (let a = -R; a <= R; a++) for (let b = -R; b <= R; b++) {
    pts.push(new THREE.Vector3(a * BLOCK - 7 + 0.5, 4.2, b * BLOCK + 3), new THREE.Vector3(a * BLOCK + 3, 4.2, b * BLOCK - 7 + 0.5));
  }
  const m = new THREE.InstancedMesh(new THREE.SphereGeometry(0.55, 8, 6), new THREE.MeshBasicMaterial({ color: new THREE.Color(0xffd08a).multiplyScalar(2.2) }), pts.length);
  pts.forEach((p, i) => { dummy.position.copy(p); dummy.scale.setScalar(1); dummy.updateMatrix(); m.setMatrixAt(i, dummy.matrix); });
  scene.add(m);
}

// السيارات: خطوط ضوء متحركة (أبيض أمامي / أحمر خلفي)
const cars = [];
const carCount = LOW ? 70 : 160;
const carGeo = new THREE.BoxGeometry(1.6, 0.5, 0.7);
const carMesh = new THREE.InstancedMesh(carGeo, new THREE.MeshBasicMaterial({ color: 0xffffff }), carCount);
const cWhite = new THREE.Color(0xfff4e0).multiplyScalar(1.5), cRed = new THREE.Color(0xff2a3a).multiplyScalar(1.6);
for (let i = 0; i < carCount; i++) {
  const alongX = rnd() < 0.5, lane = Math.floor(rnd() * (2 * N + 1)) - N, dir = rnd() < 0.5 ? 1 : -1;
  cars.push({ alongX, line: lane * BLOCK - 7 + 0.5 + (dir > 0 ? -1.2 : 1.2), dir, s: (rnd() * 2 - 1) * BLOCK * N, v: 8 + rnd() * 10 });
  carMesh.setColorAt(i, dir > 0 ? cWhite : cRed);
}
scene.add(carMesh);

// ───────────────────────── برج الصدارة الملتفّ ─────────────────────────
const towerGroup = new THREE.Group(); towerGroup.position.set(3, 0, 3); scene.add(towerGroup);
{
  const glassTex = windowTexture(16, 4, 99, COOL, 0.5);
  const glass = new THREE.MeshPhysicalMaterial({ color: 0x0f2a63, metalness: 0.75, roughness: 0.08, clearcoat: 1, clearcoatRoughness: 0.05, envMapIntensity: 0.55, emissive: 0xffffff, emissiveMap: glassTex, emissiveIntensity: 0.9 });
  const goldM = new THREE.MeshStandardMaterial({ color: GOLD, metalness: 1, roughness: 0.25, emissive: GOLD, emissiveIntensity: 0.18 });
  const floors = 20, fh = 2.9;
  const bands = []; // أحزمة ضوء ذهبية لكل طابق (موجة العرض عند الضغط)
  for (let i = 0; i < floors; i++) {
    const s = 9.5 - i * 0.1;
    const m = new THREE.Mesh(new THREE.BoxGeometry(s, fh * 0.86, s), glass);
    m.position.y = 1.2 + i * fh + fh * 0.43; m.rotation.y = i * 0.07; m.castShadow = !LOW;
    towerGroup.add(m);
    const band = new THREE.Mesh(new THREE.BoxGeometry(s + 0.9, fh * 0.9, s + 0.9), new THREE.MeshBasicMaterial({ color: new THREE.Color(GOLD_L).multiplyScalar(1.6), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }));
    band.position.copy(m.position); band.rotation.y = m.rotation.y; towerGroup.add(band); bands.push(band);
    if (i % 2 === 0) {
      const slab = new THREE.Mesh(new THREE.BoxGeometry(s + 0.5, 0.22, s + 0.5), goldM);
      slab.position.y = 1.2 + i * fh; slab.rotation.y = i * 0.07; towerGroup.add(slab);
    }
  }
  const topY = 1.2 + floors * fh;
  const crown = new THREE.Mesh(new THREE.TorusGeometry(4.6, 0.35, 12, 64), new THREE.MeshBasicMaterial({ color: new THREE.Color(GOLD_L).multiplyScalar(2) }));
  crown.rotation.x = Math.PI / 2; crown.position.y = topY + 0.6; towerGroup.add(crown);
  const spire = new THREE.Mesh(new THREE.CylinderGeometry(0.12, 0.5, 8, 8), goldM); spire.position.y = topY + 4; towerGroup.add(spire);
  // قاعدة الساحة: حلقات مضيئة
  const plaza = new THREE.Mesh(new THREE.CylinderGeometry(7.6, 7.9, 1.2, 64), new THREE.MeshStandardMaterial({ color: 0x16224a, metalness: 0.6, roughness: 0.3 }));
  plaza.position.y = 0.6; plaza.receiveShadow = true; towerGroup.add(plaza);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(7.7, 0.18, 8, 96), new THREE.MeshBasicMaterial({ color: new THREE.Color(CYAN).multiplyScalar(2.4) }));
  ring.rotation.x = Math.PI / 2; ring.position.y = 1.25; towerGroup.add(ring);
  towerGroup.userData.topY = topY;
  Object.assign(towerGroup.userData, { bands, glass, crown, ring });
}
// الشعار العائم + حلقة مدارية + شعاع
const logoGroup = new THREE.Group(); scene.add(logoGroup);
{
  const y = towerGroup.userData.topY + 17;
  logoGroup.position.set(3, y, 3);
  // قرص الشعار يواجه الكاميرا دائماً (billboard) حتى لا يظهر من الجانب
  const face = new THREE.Group(); logoGroup.add(face); logoGroup.userData.face = face;
  const glowC = document.createElement('canvas'); glowC.width = glowC.height = 128;
  { const g2 = glowC.getContext('2d'); const rg = g2.createRadialGradient(64, 64, 10, 64, 64, 64); rg.addColorStop(0, 'rgba(230,198,122,.9)'); rg.addColorStop(0.45, 'rgba(77,208,225,.35)'); rg.addColorStop(1, 'rgba(77,208,225,0)'); g2.fillStyle = rg; g2.fillRect(0, 0, 128, 128); }
  const halo = new THREE.Mesh(new THREE.PlaneGeometry(26, 26), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(glowC), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
  halo.position.z = -0.3; face.add(halo);
  const disc = new THREE.Mesh(new THREE.CircleGeometry(8.4, 64), new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide }));
  face.add(disc);
  if (CFG.logo) {
    new THREE.TextureLoader().load(CFG.logo, t => {
      t.colorSpace = THREE.SRGBColorSpace;
      const img = new THREE.Mesh(new THREE.CircleGeometry(7.9, 64), new THREE.MeshBasicMaterial({ map: t, transparent: true, side: THREE.DoubleSide }));
      img.position.z = 0.03; face.add(img);
    });
  }
  const rim = new THREE.Mesh(new THREE.TorusGeometry(8.6, 0.38, 12, 96), new THREE.MeshBasicMaterial({ color: new THREE.Color(GOLD_L).multiplyScalar(2.2) }));
  face.add(rim);
  const orbit = new THREE.Mesh(new THREE.TorusGeometry(13, 0.09, 6, 160), new THREE.MeshBasicMaterial({ color: new THREE.Color(CYAN).multiplyScalar(2) }));
  orbit.rotation.x = Math.PI / 2.4; logoGroup.add(orbit); logoGroup.userData.orbit = orbit;
  const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 3.2, y - towerGroup.userData.topY, 24, 1, true),
    new THREE.MeshBasicMaterial({ color: CYAN, transparent: true, opacity: 0.12, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
  beam.position.y = -(y - towerGroup.userData.topY) / 2; logoGroup.add(beam);
}

// ───────────────────────── المباني التفاعلية ─────────────────────────
const heroes = [];
const pickables = [];
function glassMat(color, seedN, cool) {
  const t = windowTexture(10, 16, seedN, cool ? COOL : WARM, 0.5);
  return new THREE.MeshPhysicalMaterial({ color, metalness: 0.45, roughness: 0.18, clearcoat: 0.6, envMapIntensity: 0.4, emissive: 0xffffff, emissiveMap: t, emissiveIntensity: 1.2, transparent: true, opacity: 1 });
}
function addBox(group, mat, w, h, d, x = 0, y = 0, z = 0, repY) {
  const g = new THREE.BoxGeometry(w, h, d); g.translate(0, h / 2, 0);
  const m = new THREE.Mesh(g, mat); m.position.set(x, y, z); m.castShadow = !LOW; m.receiveShadow = true;
  if (repY && mat.emissiveMap) { /* القوام مشتركة؛ التكرار محدد عند الإنشاء */ }
  group.add(m); return m;
}
heroDefs.forEach((def, idx) => {
  const g = new THREE.Group();
  g.position.set(def.bx * BLOCK + 3, 0, def.bz * BLOCK + 3);
  const facade = [];
  const goldM = new THREE.MeshStandardMaterial({ color: GOLD, metalness: 1, roughness: 0.3, emissive: GOLD, emissiveIntensity: 0.1 });
  let H = 10;
  switch (def.kind) {
    case 'glass': { H = 36; const m = glassMat(0x16305f, 31, true); m.emissiveMap.repeat.set(1, 3); facade.push(addBox(g, m, 10, H, 10)); addBox(g, goldM, 11, 0.6, 11, 0, H); addBox(g, goldM, 4, 4, 4, 0, H + 0.6); break; }
    case 'office': { H = 30; const m = glassMat(0x1b3a7a, 41, true); m.emissiveMap.repeat.set(1.5, 4); facade.push(addBox(g, m, 12, H, 9, -1, 0, 0)); const m2 = glassMat(0x1b3a7a, 42, true); m2.emissiveMap.repeat.set(1, 3); facade.push(addBox(g, m2, 6, 28, 6, 4, 0, 3)); addBox(g, goldM, 12.4, 0.5, 9.4, -1, H); break; }
    case 'mall': { H = 11; const m = glassMat(0x23305a, 51, false); m.emissiveMap.repeat.set(4, 1); facade.push(addBox(g, m, 15, H, 12)); const sign = addBox(g, new THREE.MeshBasicMaterial({ color: new THREE.Color(GOLD_L).multiplyScalar(1.8) }), 15.2, 1.1, 12.2, 0, H - 2.4); facade.push(sign); addBox(g, new THREE.MeshStandardMaterial({ color: 0x0f1a36, roughness: 0.6 }), 15.4, 0.6, 12.4, 0, H); break; }
    case 'villa': {
      H = 7; const wall = new THREE.MeshStandardMaterial({ color: 0xE9E2D4, roughness: 0.7, emissive: 0xffd9a0, emissiveIntensity: 0.05, transparent: true });
      facade.push(addBox(g, wall, 11, 6, 8, -1, 0, -1));
      const roof = new THREE.Mesh(new THREE.ConeGeometry(8, 3.4, 4), new THREE.MeshStandardMaterial({ color: 0x8C3B22, roughness: 0.55, transparent: true }));
      roof.rotation.y = Math.PI / 4; roof.position.set(-1, 7.7, -1); roof.scale.set(1, 1, 0.75); roof.castShadow = !LOW; g.add(roof); facade.push(roof);
      const win = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xffd9a0).multiplyScalar(1.6) });
      for (let k = -2; k <= 2; k++) addBox(g, win, 1.2, 1.4, 0.1, -1 + k * 2, 3, 3.05);
      const pool = addBox(g, new THREE.MeshBasicMaterial({ color: new THREE.Color(0x29B6F6).multiplyScalar(1.4) }), 6, 0.15, 3, 2, 0.05, 5.5);
      addBox(g, new THREE.MeshStandardMaterial({ color: 0x1f5e33, roughness: 0.9 }), 14, 0.08, 13, 0, 0.01, 0);
      void pool; break;
    }
    case 'apts': { H = 30; for (let k = 0; k < 2; k++) { const m = glassMat(0x2a3557, 61 + k, false); m.emissiveMap.repeat.set(1, 3); facade.push(addBox(g, m, 6, H - k * 6, 9, -3.5 + k * 7, 0, 0)); for (let f = 1; f < (H - k * 6) / 3.2; f += 1) addBox(g, new THREE.MeshStandardMaterial({ color: 0x3a4568, roughness: 0.6 }), 6.6, 0.25, 9.8, -3.5 + k * 7, f * 3.2); } break; }
    case 'school': { H = 10; const m = glassMat(0x3b3a52, 71, false); m.emissiveMap.repeat.set(4, 1.2); facade.push(addBox(g, m, 16, H, 7)); addBox(g, new THREE.MeshStandardMaterial({ color: 0x5B21B6, roughness: 0.5 }), 16.4, 0.6, 7.4, 0, H); break; }
    case 'hospital': { H = 22; const m = glassMat(0xd9dde8, 81, true); m.color.set(0x8f9ab8); m.emissiveMap.repeat.set(2, 2); facade.push(addBox(g, m, 13, H, 10)); const red = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xff3344).multiplyScalar(2) }); addBox(g, red, 4, 1.2, 0.2, 0, H - 3.5, 5.1); addBox(g, red, 1.2, 4, 0.2, 0, H - 4.9, 5.1); break; }
    case 'house': { H = 6; const wall = new THREE.MeshStandardMaterial({ color: 0xcfd6e6, roughness: 0.7, transparent: true }); facade.push(addBox(g, wall, 8, 5, 7)); const roof = new THREE.Mesh(new THREE.ConeGeometry(6, 2.6, 4), new THREE.MeshStandardMaterial({ color: 0x37474f, roughness: 0.6, transparent: true })); roof.rotation.y = Math.PI / 4; roof.position.set(0, 6.3, 0); g.add(roof); facade.push(roof); break; }
  }
  // الداخل: طوابق + نقاط المشتركين (تظهر عند الدخول)
  const inside = new THREE.Group(); inside.visible = false; g.add(inside);
  const floors = Math.min(def.floors, 14);
  const per = Math.max(1, Math.round(def.subs / floors));
  const slabMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(CYAN).multiplyScalar(1.1), transparent: true, opacity: 0.35, depthWrite: false });
  const onM = new THREE.MeshBasicMaterial({ color: new THREE.Color(0x69F0AE).multiplyScalar(2.2) });
  const offM = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xFF5252).multiplyScalar(2.2) });
  let count = 0;
  for (let f = 0; f < floors; f++) {
    const y = (f + 0.5) * (H / floors);
    const slab = new THREE.Mesh(new THREE.BoxGeometry(8, 0.12, 6.5), slabMat); slab.position.y = y; inside.add(slab);
    for (let k = 0; k < per; k++) {
      const a = (k / per) * Math.PI * 2;
      const dot = new THREE.Mesh(new THREE.SphereGeometry(0.32, 10, 8), count < def.online ? onM : offM);
      dot.position.set(Math.cos(a) * 2.6, y + 0.45, Math.sin(a) * 2);
      inside.add(dot); count++;
    }
  }
  // إطار ذهبي يظهر عند المرور
  const bbox = new THREE.Box3().setFromObject(g); const size = bbox.getSize(new THREE.Vector3());
  const edges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(size.x + 0.6, size.y + 0.6, size.z + 0.6)), new THREE.LineBasicMaterial({ color: new THREE.Color(GOLD_L).multiplyScalar(2), transparent: true, opacity: 0 }));
  edges.position.set(bbox.getCenter(new THREE.Vector3()).x - g.position.x, size.y / 2, bbox.getCenter(new THREE.Vector3()).z - g.position.z);
  g.add(edges);
  // مؤشر ONT على الأرض أمام المبنى
  const led = new THREE.Mesh(new THREE.SphereGeometry(0.55, 12, 10), def.online > 0 ? onM : offM);
  led.position.set(0, 0.9, size.z / 2 + 1.5); g.add(led);

  scene.add(g);
  const hero = { def, group: g, facade, inside, edges, height: H, hover: 0, focus: 0, led };
  heroes.push(hero);
  g.traverse(o => { if (o.isMesh && o !== led) { o.userData.hero = hero; pickables.push(o); } });
});

// ───────────────────────── شبكة الألياف ─────────────────────────
const pulses = [];
const fiberMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(CYAN).multiplyScalar(1.6) });
const pulseMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xE0FFFF).multiplyScalar(3) });
const pulseGeo = new THREE.SphereGeometry(0.42, 10, 8);
function streetPath(tx, tz, i) {
  // من البرج إلى المبنى عبر الشوارع بزوايا قائمة (الشوارع على الخطوط m*20-7)
  const y = 0.25, off = (i % 3 - 1) * 0.9;         // إزاحة صغيرة كي لا تتطابق الكوابل
  const sz = 13 + off, sx = tx + (tx >= 3 ? -10 : 10) + off;
  const pts = [new THREE.Vector3(3, y, 3), new THREE.Vector3(3, y, sz), new THREE.Vector3(sx, y, sz), new THREE.Vector3(sx, y, tz), new THREE.Vector3(tx, y, tz)];
  const path = new THREE.CurvePath();
  for (let k = 0; k < pts.length - 1; k++) if (pts[k].distanceTo(pts[k + 1]) > 0.01) path.add(new THREE.LineCurve3(pts[k], pts[k + 1]));
  return path;
}
heroes.forEach((h, i) => {
  const c = streetPath(h.group.position.x, h.group.position.z, i);
  const tube = new THREE.Mesh(new THREE.TubeGeometry(c, 200, 0.22, 6, false), fiberMat.clone());
  scene.add(tube);
  const n = 3;
  for (let k = 0; k < n; k++) {
    const m = new THREE.Mesh(pulseGeo, pulseMat); scene.add(m);
    pulses.push({ m, c, u: k / n, v: 0.12 + (i % 3) * 0.03 });
  }
  h.fiber = tube;
});

// ───────────────────────── عرض برج الصدارة (عند الضغط عليه) ─────────────────────────
const TOWER = {
  isTower: true, group: towerGroup, height: towerGroup.userData.topY, hover: 0, focus: 0,
  def: { name: 'برج الصدارة — مركز الشبكة', type: 'مركز التحكّم بالشبكة', floors: 20, subs: '12,480', online: '12,105', rx: '-18.7', fat: '312 FAT' },
};
towerGroup.traverse(o => { if (o.isMesh && !towerGroup.userData.bands.includes(o)) { o.userData.hero = TOWER; pickables.push(o); } });
logoGroup.userData.face.children.forEach(o => { if (o.isMesh) { o.userData.hero = TOWER; pickables.push(o); } });
const show = { t0: -1e9 };
// موجات صدمة ضوئية تنتشر فوق المدينة
const shocks = [0, 0.45, 0.9].map((delay, i) => {
  const m = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 160), new THREE.MeshBasicMaterial({ color: new THREE.Color(i === 1 ? GOLD_L : CYAN).multiplyScalar(2), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
  m.rotation.x = -Math.PI / 2; m.position.set(3, 0.6, 3); scene.add(m); return { m, delay };
});
// ألعاب نارية من تاج البرج
const FW = LOW ? 350 : 900;
const fwPos = new Float32Array(FW * 3), fwVel = new Float32Array(FW * 3), fwCol = new Float32Array(FW * 3);
for (let i = 0; i < FW; i++) { const c = new THREE.Color(i % 3 ? GOLD_L : CYAN).multiplyScalar(2.2); fwCol.set([c.r, c.g, c.b], i * 3); }
const fwGeo = new THREE.BufferGeometry(); fwGeo.setAttribute('position', new THREE.BufferAttribute(fwPos, 3)); fwGeo.setAttribute('color', new THREE.BufferAttribute(fwCol, 3));
const fwMat = new THREE.PointsMaterial({ size: 1.1, vertexColors: true, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false });
const fireworks = new THREE.Points(fwGeo, fwMat); fireworks.frustumCulled = false; scene.add(fireworks);
function resetFireworks() {
  const top = towerGroup.userData.topY + 2;
  for (let i = 0; i < FW; i++) {
    fwPos.set([3, top, 3], i * 3);
    const th = Math.random() * Math.PI * 2, ph = Math.acos(Math.random() * 1.6 - 0.6), sp = 14 + Math.random() * 26;
    fwVel.set([Math.sin(ph) * Math.cos(th) * sp, Math.cos(ph) * sp + 8, Math.sin(ph) * Math.sin(th) * sp], i * 3);
  }
  fwGeo.attributes.position.needsUpdate = true;
}
// أقواس بيانات من التاج إلى أنحاء المدينة (تُرسم تدريجياً)
const arcs = [];
for (let i = 0; i < (LOW ? 14 : 28); i++) {
  const a = (i / (LOW ? 14 : 28)) * Math.PI * 2 + Math.random() * 0.2, r = 70 + Math.random() * 150;
  const end = new THREE.Vector3(3 + Math.cos(a) * r, 0.5, 3 + Math.sin(a) * r);
  const start = new THREE.Vector3(3, towerGroup.userData.topY + 1, 3);
  const mid = start.clone().lerp(end, 0.5).setY(towerGroup.userData.topY + 25 + r * 0.25);
  const geo = new THREE.TubeGeometry(new THREE.QuadraticBezierCurve3(start, mid, end), 80, 0.12, 6, false);
  const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color: new THREE.Color(i % 2 ? CYAN : GOLD_L).multiplyScalar(2.2), transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false }));
  m.visible = false; geo.setDrawRange(0, 0); scene.add(m);
  arcs.push({ m, n: geo.index.count, delay: 0.6 + Math.random() * 1.2 });
}
function startShow() { show.t0 = clock.elapsedTime; resetFireworks(); arcs.forEach(a => { a.m.visible = true; }); }

// ───────────────────────── ما بعد المعالجة ─────────────────────────
const composer = new EffectComposer(renderer);
composer.addPass(new RenderPass(scene, camera));
const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), LOW ? 0.7 : 0.9, 0.5, 1.15);
composer.addPass(bloom);
composer.addPass(new OutputPass());

// ───────────────────────── التحكّم والتفاعل ─────────────────────────
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true; controls.dampingFactor = 0.06;
controls.enablePan = false; controls.minDistance = 35; controls.maxDistance = 320;
controls.minPolarAngle = 0.3; controls.maxPolarAngle = 1.25;
controls.autoRotate = true; controls.autoRotateSpeed = 0.35;
controls.target.set(3, 34, 3);
controls.enabled = CFG.interactive !== false;
let idleTimer = null;
controls.addEventListener('start', () => { controls.autoRotate = false; clearTimeout(idleTimer); });
controls.addEventListener('end', () => { clearTimeout(idleTimer); idleTimer = setTimeout(() => { if (!focused) controls.autoRotate = true; }, 6000); });

const ray = new THREE.Raycaster(); const mouse = new THREE.Vector2(); let hovered = null, focused = null;
const par = { x: 0, y: 0, gx: 0, gy: 0 };
const labelEl = document.getElementById('label'), infoEl = document.getElementById('info'), hintEl = document.getElementById('hint');
let lastPick = 0, downAt = null;

function setMouse(e) { const r = canvas.getBoundingClientRect(); mouse.x = ((e.clientX - r.left) / r.width) * 2 - 1; mouse.y = -((e.clientY - r.top) / r.height) * 2 + 1; }
function pick() { ray.setFromCamera(mouse, camera); const hit = ray.intersectObjects(pickables, false)[0]; return hit ? hit.object.userData.hero : null; }

canvas.addEventListener('pointermove', e => {
  setMouse(e); par.gx = mouse.x; par.gy = mouse.y;
  const now = performance.now();
  if (now - lastPick > 45 && !e.buttons) { lastPick = now; hovered = CFG.interactive === false ? null : pick(); canvas.style.cursor = hovered ? 'pointer' : 'grab'; }
});
canvas.addEventListener('pointerleave', () => { hovered = null; par.gx = par.gy = 0; });
canvas.addEventListener('pointerdown', e => { downAt = { x: e.clientX, y: e.clientY }; });
canvas.addEventListener('pointerup', e => {
  if (!downAt || CFG.interactive === false) return;
  const moved = Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y); downAt = null;
  if (moved > 6) return;
  setMouse(e); const h = pick();
  focus(h && h !== focused ? h : null);
});
window.addEventListener('keydown', e => { if (e.key === 'Escape') focus(null); });
document.getElementById('close').addEventListener('click', () => focus(null));

// انتقال الكاميرا بسلاسة
let tween = null;
function flyTo(pos, target, ms = 1300) {
  tween = { t0: performance.now(), ms, p0: camera.position.clone(), p1: pos, q0: controls.target.clone(), q1: target };
}
const HOME = { pos: new THREE.Vector3(140, 105, 175), target: new THREE.Vector3(3, 34, 3) };
function focus(h) {
  focused = h;
  controls.autoRotateSpeed = 0.35;
  if (h && h.isTower) {
    // عرض مبهر: الكاميرا تدور حول البرج + موجة ضوء + ألعاب نارية + أقواس بيانات + موجات صدمة
    const top = towerGroup.userData.topY;
    flyTo(new THREE.Vector3(3 + 85, top * 0.95, 3 + 85), new THREE.Vector3(3, top * 0.8, 3), 1600);
    setTimeout(() => { if (focused === TOWER) { controls.autoRotate = true; controls.autoRotateSpeed = 2.2; } }, 1600);
    startShow();
  }
  if (h) {
    if (!h.isTower) controls.autoRotate = false;
    const gp = h.group.position, dist = 28 + h.height * 0.9;
    if (!h.isTower) {
    const dir = new THREE.Vector3(gp.x, 0, gp.z).normalize(); if (!isFinite(dir.x)) dir.set(1, 0, 1).normalize();
    const side = new THREE.Vector3(-dir.z, 0, dir.x).multiplyScalar(dist * 0.45);
    flyTo(new THREE.Vector3(gp.x, 0, gp.z).add(dir.multiplyScalar(dist)).add(side).setY(h.height * 0.7 + 12), new THREE.Vector3(gp.x, h.height * 0.45, gp.z));
    }
    const d = h.def;
    infoEl.querySelector('.n').textContent = d.name;
    infoEl.querySelector('.t').textContent = d.type + ' · ' + d.floors + (d.floors > 10 ? ' طابقاً' : ' طوابق');
    infoEl.querySelector('.subs').textContent = d.subs;
    infoEl.querySelector('.on').textContent = d.online;
    infoEl.querySelector('.rx').textContent = d.rx;
    infoEl.querySelector('.fat').textContent = d.fat;
    const ns = parseFloat(String(d.subs).replace(/,/g, '')), no = parseFloat(String(d.online).replace(/,/g, ''));
    infoEl.querySelector('.bar i').style.width = (ns ? no / ns * 100 : 0) + '%';
    infoEl.classList.add('on'); hintEl.classList.add('off');
  } else {
    flyTo(HOME.pos.clone(), HOME.target.clone());
    infoEl.classList.remove('on'); hintEl.classList.remove('off');
    clearTimeout(idleTimer); idleTimer = setTimeout(() => { if (!focused) controls.autoRotate = true; }, 4000);
  }
}

// ───────────────────────── الحجم وإزاحة المشهد ─────────────────────────
let W = 1, H = 1;
function resize() {
  W = window.innerWidth; H = window.innerHeight;
  renderer.setSize(W, H, false); composer.setSize(W, H);
  bloom.setSize(Math.round(W * pixelRatio / 2), Math.round(H * pixelRatio / 2));
  camera.aspect = W / H; camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize); resize();

// ───────────────────────── الحلقة ─────────────────────────
const clock = new THREE.Clock(); let running = true, frames = 0, acc = 0, degraded = LOW;
document.addEventListener('visibilitychange', () => { running = !document.hidden; if (running) { clock.getDelta(); requestAnimationFrame(loop); } });
const tmpV = new THREE.Vector3();
const ease = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

function loop() {
  if (!running) return;
  const dt = Math.min(clock.getDelta(), 0.05), t = clock.elapsedTime;

  // جودة تكيّفية: إن كان الأداء ضعيفاً نخفّض الدقة ونلغي الظلال
  frames++; acc += dt;
  if (!degraded && t > 3 && t < 6 && frames > 30 && acc / frames > 0.03) {
    degraded = true; pixelRatio = 1; renderer.setPixelRatio(1); renderer.shadowMap.enabled = false; resize();
  }

  // الكاميرا
  if (tween) {
    const k = Math.min(1, (performance.now() - tween.t0) / tween.ms), e = ease(k);
    camera.position.lerpVectors(tween.p0, tween.p1, e); controls.target.lerpVectors(tween.q0, tween.q1, e);
    if (k >= 1) tween = null;
  }
  controls.update();
  par.x += (par.gx - par.x) * 0.05; par.y += (par.gy - par.y) * 0.05;
  const sx = (CFG.shiftX || 0) + par.x * -18, sy = par.y * 10;
  camera.setViewOffset(W, H, -sx, sy, W, H);

  // الشعار والبرج
  logoGroup.position.y = towerGroup.userData.topY + 17 + Math.sin(t * 1.4) * 0.8;
  logoGroup.userData.face.quaternion.copy(camera.quaternion);
  if (t - show.t0 < 2.2) logoGroup.userData.face.rotateZ((t - show.t0) * Math.PI * 2 / 2.2);
  logoGroup.userData.orbit.rotation.z = t * 0.8;

  // عرض البرج
  const st = t - show.t0, on = focused === TOWER;
  TOWER.hover += ((hovered === TOWER && !focused ? 1 : 0) - TOWER.hover) * 0.15;
  TOWER.focus += ((on ? 1 : 0) - TOWER.focus) * 0.06;
  const glowK = Math.max(TOWER.hover * 0.5, TOWER.focus * 0.45, st < 4 ? Math.exp(-st * 0.6) : 0);
  { const ud = towerGroup.userData, top = ud.topY;
    const front = st * 22 - 4;
    ud.bands.forEach(bd => {
      const wave = st < 5 ? Math.exp(-Math.pow(bd.position.y - front, 2) / 22) : 0;
      bd.material.opacity = Math.min(0.6, wave * 0.6 + TOWER.hover * 0.18 + TOWER.focus * 0.12 * (0.6 + 0.4 * Math.sin(t * 3 + bd.position.y * 0.3)));
    });
    ud.glass.emissiveIntensity = 0.9 + glowK * 0.7;
    ud.crown.material.color.setHex(GOLD_L).multiplyScalar(2 + glowK * 1.5 + (st < 2 ? 2.5 * Math.exp(-st * 2) : 0));
    ud.ring.material.color.setHex(CYAN).multiplyScalar(2.4 + glowK * 2.5);
    shocks.forEach(sh => { const k = st - sh.delay; if (k > 0 && k < 3.4) { sh.m.scale.setScalar(8 + k * 95); sh.m.material.opacity = 0.7 * (1 - k / 3.4); } else sh.m.material.opacity = 0; });
    if (st < 5) {
      for (let i = 0; i < FW; i++) { const j = i * 3; fwVel[j + 1] -= 18 * dt; fwPos[j] += fwVel[j] * dt; fwPos[j + 1] += fwVel[j + 1] * dt; fwPos[j + 2] += fwVel[j + 2] * dt; }
      fwGeo.attributes.position.needsUpdate = true; fwMat.opacity = Math.max(0, 1 - st / 4.5);
    } else fwMat.opacity = 0;
    arcs.forEach(a => {
      const k = Math.min(1, Math.max(0, (st - a.delay) / 1.4));
      a.m.geometry.setDrawRange(0, Math.floor(a.n * k / 3) * 3);
      a.m.material.opacity = on ? (st < 5 ? 0.8 : 0.35 + 0.2 * Math.sin(t * 2 + a.delay * 5)) : Math.max(0, a.m.material.opacity - dt * 0.8);
      if (!on && a.m.material.opacity <= 0) a.m.visible = false;
    });
    void top;
  }
  const lscale = 1 + (st < 2.5 ? 0.6 * Math.sin(Math.min(1, st / 2.5) * Math.PI) : 0) + TOWER.hover * 0.12;
  logoGroup.userData.face.scale.setScalar(lscale);

  // نبضات الألياف (أسرع وأسطع أثناء العرض)
  const pk = 1 + glowK * 3;
  pulses.forEach(p => { p.u = (p.u + p.v * pk * dt) % 1; p.c.getPointAt(p.u, tmpV); p.m.position.copy(tmpV); });

  // السيارات
  const lim = BLOCK * N;
  cars.forEach((c, i) => {
    c.s += c.dir * c.v * dt; if (c.s > lim) c.s = -lim; if (c.s < -lim) c.s = lim;
    if (c.alongX) { dummy.position.set(c.s, 0.45, c.line); dummy.rotation.set(0, 0, 0); } else { dummy.position.set(c.line, 0.45, c.s); dummy.rotation.set(0, Math.PI / 2, 0); }
    dummy.scale.setScalar(1); dummy.updateMatrix(); carMesh.setMatrixAt(i, dummy.matrix);
  });
  carMesh.instanceMatrix.needsUpdate = true;

  // وميض أضواء التحذير
  blinkMat.color.setRGB(1.6 * (0.5 + 0.5 * Math.sin(t * 3)), 0.15, 0.2);

  // المباني التفاعلية: مرور/دخول
  heroes.forEach(h => {
    h.hover += ((h === hovered && !focused ? 1 : 0) - h.hover) * 0.15;
    h.focus += ((h === focused ? 1 : 0) - h.focus) * 0.08;
    h.edges.material.opacity = Math.max(h.hover, h.focus * 0.6);
    h.facade.forEach(m => {
      const mat = m.material;
      mat.opacity = 1 - h.focus * 0.82; mat.depthWrite = h.focus < 0.3;
      if (mat.emissiveIntensity !== undefined && mat.emissiveMap) mat.emissiveIntensity = 1.2 + h.hover * 1.0;
    });
    h.inside.visible = h.focus > 0.05;
    h.inside.scale.setScalar(0.85 + h.focus * 0.15);
    h.led.scale.setScalar(1 + 0.35 * Math.sin(t * 4 + h.group.position.x));
    h.fiber.material.color.setHex(CYAN).multiplyScalar(1.6 + Math.max(h.hover, h.focus) * 1.8);
  });
  // تسمية المبنى عند المرور
  if (hovered && !focused) {
    tmpV.set(hovered.group.position.x, hovered.height + 6, hovered.group.position.z).project(camera);
    labelEl.style.transform = `translate(${(tmpV.x * 0.5 + 0.5) * W}px, ${(-tmpV.y * 0.5 + 0.5) * H}px) translate(-50%, -100%)`;
    labelEl.textContent = hovered.isTower ? 'برج الصدارة — اضغط للعرض' : hovered.def.name; labelEl.classList.add('on');
  } else labelEl.classList.remove('on');

  composer.render();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
window.SD_READY = true;
