const admin = require('firebase-admin');
const crypto = require('crypto');

// تهيئة Firebase Admin للمشروع الصحيح web-app-sadara
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

// دالة لتشفير كلمة المرور
function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

// المستخدمين الجدد
const newUsers = [
  {
    username: 'manager001',
    password: 'manager001',
    fullName: 'أحمد محمد',
    phone: '0501234567',
    code: 'M001',
    role: 'manager',
    department: 'الإدارة',
    center: 'الرياض',
    salary: '15000',
    isActive: true,
    firstSystemPermissions: {
      attendance: true, agent: true, tasks: true, zones: true, ai_search: true
    },
    secondSystemPermissions: {
      users: true, subscriptions: true, tasks: true, zones: true, accounts: true,
      account_records: true, export: true, agents: true, google_sheets: true,
      whatsapp: true, wallet_balance: true, expiring_soon: true, quick_search: true,
      technicians: true, transactions: true, notifications: true, audit_logs: true,
      whatsapp_link: true, whatsapp_settings: true, plans_bundles: true,
      whatsapp_business_api: true, whatsapp_bulk_sender: true,
      whatsapp_conversations_fab: true, local_storage: true, local_storage_import: true
    }
  },
  {
    username: 'technician001',
    password: 'technician001',
    fullName: 'خالد عبدالله',
    phone: '0507654321',
    code: 'T001',
    role: 'technician',
    department: 'الفنيين',
    center: 'جدة',
    salary: '8000',
    isActive: true,
    firstSystemPermissions: {
      attendance: true, agent: false, tasks: true, zones: true, ai_search: false
    },
    secondSystemPermissions: {
      users: false, subscriptions: true, tasks: true, zones: true, accounts: true,
      account_records: true, export: false, agents: false, google_sheets: false,
      whatsapp: false, wallet_balance: false, expiring_soon: true, quick_search: true,
      technicians: false, transactions: false, notifications: true, audit_logs: false,
      whatsapp_link: false, whatsapp_settings: false, plans_bundles: false,
      whatsapp_business_api: false, whatsapp_bulk_sender: false,
      whatsapp_conversations_fab: false, local_storage: false, local_storage_import: false
    }
  },
  {
    username: 'employee001',
    password: 'employee001',
    fullName: 'سارة أحمد',
    phone: '0551234567',
    code: 'E001',
    role: 'employee',
    department: 'خدمة العملاء',
    center: 'الدمام',
    salary: '6000',
    isActive: true,
    firstSystemPermissions: {
      attendance: true, agent: false, tasks: false, zones: false, ai_search: true
    },
    secondSystemPermissions: {
      users: false, subscriptions: true, tasks: false, zones: false, accounts: true,
      account_records: true, export: false, agents: false, google_sheets: false,
      whatsapp: false, wallet_balance: false, expiring_soon: true, quick_search: true,
      technicians: false, transactions: false, notifications: true, audit_logs: false,
      whatsapp_link: false, whatsapp_settings: false, plans_bundles: false,
      whatsapp_business_api: false, whatsapp_bulk_sender: false,
      whatsapp_conversations_fab: false, local_storage: false, local_storage_import: false
    }
  },
  {
    username: 'leader001',
    password: 'leader001',
    fullName: 'محمد سعيد',
    phone: '0561112233',
    code: 'L001',
    role: 'technical_leader',
    department: 'الفنيين',
    center: 'مكة',
    salary: '10000',
    isActive: true,
    firstSystemPermissions: {
      attendance: true, agent: true, tasks: true, zones: true, ai_search: true
    },
    secondSystemPermissions: {
      users: false, subscriptions: true, tasks: true, zones: true, accounts: true,
      account_records: true, export: true, agents: true, google_sheets: false,
      whatsapp: false, wallet_balance: true, expiring_soon: true, quick_search: true,
      technicians: true, transactions: true, notifications: true, audit_logs: false,
      whatsapp_link: false, whatsapp_settings: false, plans_bundles: false,
      whatsapp_business_api: false, whatsapp_bulk_sender: false,
      whatsapp_conversations_fab: false, local_storage: false, local_storage_import: false
    }
  }
];

async function setupUsersInWebAppSadara() {
  try {
    console.log('🔌 متصل بـ: web-app-sadara');
    console.log('');
    
    const tenantId = 'demo001';
    
    // التحقق من وجود الشركة
    const tenantDoc = await db.collection('tenants').doc(tenantId).get();
    if (!tenantDoc.exists) {
      console.log('❌ الشركة demo001 غير موجودة! جاري إنشائها...');
      await db.collection('tenants').doc(tenantId).set({
        name: 'شركة تجريبية',
        code: 'اهلا',
        address: 'الرياض، المملكة العربية السعودية',
        phone: '+966500000000',
        isActive: true,
        maxUsers: 50,
        subscriptionPlan: 'yearly',
        subscriptionStart: admin.firestore.Timestamp.now(),
        subscriptionEnd: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)),
        createdAt: admin.firestore.Timestamp.now(),
        createdBy: 'system',
        logo: null
      });
      console.log('✅ تم إنشاء الشركة');
    } else {
      console.log('✅ الشركة موجودة: ' + tenantDoc.data().name);
    }
    console.log('');
    
    // مسح المستخدمين الحاليين
    console.log('🗑️ مسح المستخدمين الحاليين...');
    const usersSnapshot = await db.collection('tenants').doc(tenantId).collection('users').get();
    const batch = db.batch();
    usersSnapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
    console.log(`✅ تم مسح ${usersSnapshot.size} مستخدم`);
    console.log('');
    
    // إنشاء المستخدمين الجدد
    console.log('👥 إنشاء المستخدمين الجدد...\n');
    
    for (const user of newUsers) {
      const passwordHash = hashPassword(user.password);
      
      await db.collection('tenants').doc(tenantId).collection('users').add({
        username: user.username,
        passwordHash: passwordHash,
        fullName: user.fullName,
        phone: user.phone,
        code: user.code,
        role: user.role,
        department: user.department,
        center: user.center,
        salary: user.salary,
        isActive: user.isActive,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: 'system',
        firstSystemPermissions: user.firstSystemPermissions,
        secondSystemPermissions: user.secondSystemPermissions
      });
      
      console.log(`✅ ${user.fullName} (@${user.username}) - ${user.role}`);
    }
    
    console.log('\n✅ تم الانتهاء! تم إنشاء ' + newUsers.length + ' مستخدم في web-app-sadara');
    console.log('\n📋 بيانات تسجيل الدخول:');
    console.log('كود الشركة: اهلا\n');
    newUsers.forEach(u => console.log(`  ${u.username} / ${u.password}`));
    
  } catch (error) {
    console.error('❌ خطأ:', error.message);
  } finally {
    process.exit();
  }
}

setupUsersInWebAppSadara();
