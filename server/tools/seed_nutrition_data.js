// server/tools/seed_nutrition_data.js
import 'dotenv/config';
import admin from 'firebase-admin';

const PROJECT_ID = 'cal-ai-clone-e57ea';

// ---------- Firebase Admin init (uses FIREBASE_SERVICE_ACCOUNT from .env) ----------
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
  console.log('🔐 Env blob present:', !!process.env.FIREBASE_SERVICE_ACCOUNT);
}

const db = admin.firestore();

// ---------- Seeder ----------
class NutritionSeeder {
  static formatDateKey(date) {
    return date.toISOString().split('T')[0];
  }

  static randomVariation(min, max) {
    return min + (Math.random() * (max - min));
  }

  static generateRealisticDay(targets, date) {
    const dayOfWeek = date.getDay();
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    const calorieVariation = isWeekend
      ? this.randomVariation(0.8, 1.2)
      : this.randomVariation(0.9, 1.1);

    const proteinVariation = this.randomVariation(0.85, 1.1);
    const carbVariation = this.randomVariation(0.7, 1.3);
    const fatVariation = this.randomVariation(0.8, 1.2);

         const calories = Math.round(targets.calories * calorieVariation);
     const protein  = Math.round(targets.protein  * proteinVariation);
     const carbs    = Math.round(targets.carbs    * carbVariation);
     const fat      = Math.round(targets.fat      * fatVariation);

     return { calories, protein, carbs, fat };
  }

  static async seedPastMonth(uid) {
    console.log(`🌱 Seeding nutrition data for user: ${uid}`);

    const today = new Date();
    const thirtyDaysAgo = new Date(today.getTime() - (30 * 24 * 60 * 60 * 1000));
    console.log(`📅 Date range: ${this.formatDateKey(thirtyDaysAgo)} → ${this.formatDateKey(new Date(today.getTime() - 24*60*60*1000))}`);

    const targets = { calories: 3247, protein: 177, carbs: 432, fat: 90 };

    let batch = db.batch();
    let pending = 0;
    let written = 0;

    for (let d = new Date(thirtyDaysAgo); d < today; d.setDate(d.getDate() + 1)) {
      const date = new Date(d); // clone
      const dateKey = this.formatDateKey(date);

      // Skip if exists
      const existing = await db.collection('daily_nutrition_summaries')
        .where('uid', '==', uid)
        .where('date', '==', dateKey)
        .limit(1)
        .get();

      if (!existing.empty) {
        console.log(`⏭️  ${dateKey} exists, skipping`);
        continue;
      }

      const daily = this.generateRealisticDay(targets, date);
      const ref = db.collection('daily_nutrition_summaries').doc();
             batch.set(ref, {
         uid,
         date: dateKey,
         total_calories: daily.calories,
         total_protein_g: daily.protein,
         total_carb_g: daily.carbs,
         total_fat_g: daily.fat,
         created_at: admin.firestore.FieldValue.serverTimestamp(),
       });

      pending++;
      written++;
      console.log(`📊 queued ${dateKey}: ${daily.calories} kcal, ${daily.protein} g P`);

      if (pending === 10) {
        await batch.commit();
        console.log('💾 committed batch of 10');
        batch = db.batch(); // NEW batch
        pending = 0;
      }
    }

    if (pending > 0) {
      await batch.commit();
      console.log(`💾 committed final batch of ${pending}`);
    }

    console.log(`✅ wrote ${written} new day(s)`);
  }

  static async seedSampleDays(uid) {
    const sampleDates = [
      new Date(Date.now() - 1 * 24 * 60 * 60 * 1000),
      new Date(Date.now() - 2 * 24 * 60 * 60 * 1000),
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000),
    ];

    for (const date of sampleDates) {
      const dateKey = this.formatDateKey(date);
             await db.collection('daily_nutrition_summaries').add({
         uid,
         date: dateKey,
         total_calories: 3100,
         total_protein_g: 170,
         total_carb_g: 380,
         total_fat_g: 85,
         created_at: admin.firestore.FieldValue.serverTimestamp(),
       });
      console.log(`✅ Created sample data for ${dateKey}`);
    }
  }
}

// ---------- Entrypoint ----------
async function main() {
  const uid = 'iCqnjbHxKfZgT4Rx9Jg9LUge2cQ2'; // your user ID
  try {
    console.log('🚀 Starting nutrition data seeding…\n');

    // Choose one:
    // await NutritionSeeder.seedSampleDays(uid);
    await NutritionSeeder.seedPastMonth(uid);

         // Probe read (optional sanity check)
     const snap = await db.collection('daily_nutrition_summaries')
       .where('uid', '==', uid)
       .limit(3)
       .get();
     
     console.log(`\n🔍 Found ${snap.size} existing entries in database`);
     console.log('🎉 Seeding completed successfully!');
     process.exit(0);
   } catch (error) {
     console.error('❌ Error during seeding:', error);
     process.exit(1);
   }
}

// Run the script
main();
