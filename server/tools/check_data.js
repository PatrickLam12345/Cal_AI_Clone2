// server/tools/check_data.js
import 'dotenv/config';
import admin from 'firebase-admin';

const PROJECT_ID = 'cal-ai-clone-e57ea';

// ---------- Firebase Admin init ----------
function getCredAndProject() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT not set in .env');
  }
  const json = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  if (!json.project_id) throw new Error('Service account JSON missing "project_id"');
  return { cred: admin.credential.cert(json), projectId: PROJECT_ID || json.project_id };
}

if (!admin.apps.length) {
  const { cred, projectId } = getCredAndProject();
  admin.initializeApp({ credential: cred, projectId });
  console.log('✅ Firebase initialized for project:', admin.app().options.projectId);
}

const db = admin.firestore();

async function checkData() {
  const uid = 'iCqnjbHxKfZgT4Rx9Jg9LUge2cQ2';
  const today = new Date();
  const todayKey = today.toISOString().split('T')[0]; // YYYY-MM-DD format
  
  console.log(`🔍 Checking data for user: ${uid}`);
  console.log(`📅 Today's date key: ${todayKey}`);
  console.log(`🕐 Current time: ${today.toISOString()}`);
  
  try {
    // Check all entries for this user
    const allQuery = await db.collection('food_log_entries')
      .where('uid', '==', uid)
      .get();
    
    console.log(`\n📊 Total entries for user: ${allQuery.docs.length}`);
    
    if (allQuery.docs.length > 0) {
      console.log('\n📋 All entries:');
      allQuery.docs.forEach((doc, index) => {
        const data = doc.data();
        console.log(`${index + 1}. ${data.name} - Date: ${data.date} - Created: ${data.created_at?.toDate?.()?.toISOString() || data.created_at}`);
      });
    }
    
    // Check today's entries specifically
    const todayQuery = await db.collection('food_log_entries')
      .where('uid', '==', uid)
      .where('date', '==', todayKey)
      .get();
      
    console.log(`\n📅 Today's entries (${todayKey}): ${todayQuery.docs.length}`);
    
    if (todayQuery.docs.length > 0) {
      console.log('\n🍽️ Today\'s meals:');
      todayQuery.docs.forEach((doc, index) => {
        const data = doc.data();
        console.log(`${index + 1}. ${data.name} - ${data.kcal} kcal - Source: ${data.source} - Image: ${data.image_url ? 'Yes' : 'No'}`);
      });
    } else {
      console.log('❌ No meals found for today!');
    }
    
  } catch (error) {
    console.error('❌ Error checking data:', error);
  }
}

checkData().then(() => {
  console.log('\n✅ Data check completed!');
  process.exit(0);
}).catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});
