// Set User Password in Firebase
const admin = require('firebase-admin');
const crypto = require('crypto');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

// SHA-256 Hash Function (same as in Flutter app)
function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

async function setUserPasswords() {
  try {
    console.log('Setting user passwords...\n');

    // Password for user "123456"
    const employeePassword = '123456';
    const employeeHash = hashPassword(employeePassword);
    
    await db.collection('tenants').doc('demo001').collection('users').doc('employee001').update({
      passwordHash: employeeHash
    });
    
    console.log('✓ Updated employee001:');
    console.log(`  Username: 123456`);
    console.log(`  Password: ${employeePassword}`);
    console.log('');

    // Password for manager "1"
    const managerPassword = '123456';
    const managerHash = hashPassword(managerPassword);
    
    await db.collection('tenants').doc('demo001').collection('users').doc('manager001').update({
      passwordHash: managerHash
    });
    
    console.log('✓ Updated manager001:');
    console.log(`  Username: 1`);
    console.log(`  Password: ${managerPassword}`);
    console.log('');

    console.log('============================================================');
    console.log('Login Credentials:');
    console.log('============================================================');
    console.log('Tenant Code: اهلا');
    console.log('');
    console.log('Employee:');
    console.log('  Username: 123456');
    console.log('  Password: 123456');
    console.log('');
    console.log('Manager:');
    console.log('  Username: 1');
    console.log('  Password: 123456');
    console.log('============================================================');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

setUserPasswords();
