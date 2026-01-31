// Check and Set Password to "1"
const admin = require('firebase-admin');
const crypto = require('crypto');
const serviceAccount = require('./web-app-sadara-firebase-adminsdk-fbsvc-b1c405cb4d.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'web-app-sadara'
});

const db = admin.firestore();

function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

async function checkAndSetPassword() {
  try {
    // Get current user data
    const userDoc = await db.collection('tenants').doc('demo001').collection('users').doc('manager001').get();
    const userData = userDoc.data();
    
    console.log('Current user data:');
    console.log('Username:', userData.username);
    console.log('Current passwordHash:', userData.passwordHash);
    console.log('');
    
    // Set password to "1"
    const newPassword = '1';
    const newHash = hashPassword(newPassword);
    
    console.log('Setting new password...');
    console.log('New password:', newPassword);
    console.log('New hash:', newHash);
    console.log('');
    
    await db.collection('tenants').doc('demo001').collection('users').doc('manager001').update({
      passwordHash: newHash
    });
    
    console.log('✅ Password updated successfully!');
    console.log('');
    console.log('============================================================');
    console.log('Login with:');
    console.log('============================================================');
    console.log('Tenant Code: اهلا');
    console.log('Username: 1');
    console.log('Password: 1');
    console.log('============================================================');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkAndSetPassword();
