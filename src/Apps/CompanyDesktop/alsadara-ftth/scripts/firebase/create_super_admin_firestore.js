// إنشاء Super Admin في Firestore
// هذا السكريبت يعمل مع أي Firebase project

const { initializeApp } = require('firebase/app');
const { getFirestore, collection, addDoc, getDocs, query, where } = require('firebase/firestore');
const crypto = require('crypto');

// إعدادات Firebase (من التطبيق)
const firebaseConfig = {
  apiKey: "AIzaSyDWL8vqXqH4_6v8JXmZ0ZfD8gQX4qY5k8M",
  authDomain: "web-app-sadara.firebaseapp.com",
  projectId: "web-app-sadara",
  storageBucket: "web-app-sadara.appspot.com",
  messagingSenderId: "950658836305",
  appId: "1:950658836305:web:abc123def456"
};

// تهيئة Firebase
const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

// تشفير كلمة المرور
function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

async function createSuperAdmin() {
  console.log('🔐 إنشاء مدير النظام (Super Admin)...\n');

  const username = 'superadmin';
  const password = 'Admin@123';
  const hashedPassword = hashPassword(password);

  try {
    // التحقق من وجود المستخدم
    const q = query(collection(db, 'super_admins'), where('username', '==', username));
    const existing = await getDocs(q);

    if (!existing.empty) {
      console.log('⚠️ مدير النظام موجود بالفعل!');
      existing.forEach(doc => {
        console.log(`   ID: ${doc.id}`);
        console.log(`   Username: ${doc.data().username}`);
      });
      process.exit(0);
    }

    // إنشاء المستخدم
    const docRef = await addDoc(collection(db, 'super_admins'), {
      username: username,
      passwordHash: hashedPassword,
      name: 'مدير النظام',
      email: 'admin@alsadara.com',
      isActive: true,
      createdAt: new Date(),
      lastLogin: null
    });

    console.log('✅ تم إنشاء مدير النظام بنجاح!\n');
    console.log('═══════════════════════════════════════');
    console.log('   بيانات تسجيل الدخول');
    console.log('═══════════════════════════════════════');
    console.log(`   اسم الشركة: 1`);
    console.log(`   اسم المستخدم: ${username}`);
    console.log(`   كلمة المرور: ${password}`);
    console.log('═══════════════════════════════════════');
    console.log(`\n   Document ID: ${docRef.id}`);

  } catch (error) {
    console.error('❌ خطأ:', error.message);
  }

  process.exit(0);
}

createSuperAdmin();
