// server/tools/seed_meals_with_storage.js
import 'dotenv/config';
import admin from 'firebase-admin';
import fetch from 'node-fetch';
import fs from 'fs/promises';
import path from 'path';

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
  admin.initializeApp({ 
    credential: cred, 
    projectId,
    storageBucket: `${PROJECT_ID}.appspot.com`
  });
  console.log('✅ Firebase initialized for project:', admin.app().options.projectId);
}

const db = admin.firestore();
const storage = admin.storage();

// ---------- Sample images URLs ----------
const sampleImageUrls = [
  'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=400&h=400&fit=crop', // Grilled chicken
  'https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=400&h=400&fit=crop', // Avocado toast
  'https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400&h=400&fit=crop', // Greek yogurt
  'https://images.unsplash.com/photo-1467003909585-2f8a72700288?w=400&h=400&fit=crop', // Salmon dinner
  'https://images.unsplash.com/photo-1553530979-67eb72a56c8b?w=400&h=400&fit=crop'  // Smoothie
];

// ---------- Sample meal data ----------
const sampleMeals = [
  {
    name: 'Grilled Chicken Breast with Vegetables',
    kcal: 450,
    protein_g: 35,
    carb_g: 15,
    fat_g: 18,

    source: 'scan',
    imageIndex: 0,
    ingredients: [
      {
        name: 'Grilled Chicken Breast',
        portion_desc: '150 g',
        portion_grams: 150,
        calories: 250,
        protein: 25,
        carbs: 0,
        fat: 8,

      },
      {
        name: 'Mixed Vegetables',
        portion_desc: '100 g',
        portion_grams: 100,
        calories: 200,
        protein: 10,
        carbs: 15,
        fat: 10,

      }
    ]
  },
  {
    name: 'Avocado Toast with Eggs',
    kcal: 380,
    protein_g: 18,
    carb_g: 25,
    fat_g: 22,

    source: 'scan',
    imageIndex: 1,
    ingredients: [
      {
        name: 'Whole Grain Bread',
        portion_desc: '2 slices',
        portion_grams: 60,
        calories: 140,
        protein: 6,
        carbs: 20,
        fat: 3,

      },
      {
        name: 'Avocado',
        portion_desc: '1/2 medium',
        portion_grams: 75,
        calories: 120,
        protein: 2,
        carbs: 4,
        fat: 11,

      },
      {
        name: 'Scrambled Eggs',
        portion_desc: '2 large',
        portion_grams: 100,
        calories: 120,
        protein: 10,
        carbs: 1,
        fat: 8,

      }
    ]
  },
  {
    name: 'Greek Yogurt with Berries',
    kcal: 220,
    protein_g: 20,
    carb_g: 25,
    fat_g: 6,

    source: 'scan',
    imageIndex: 2,
    ingredients: [
      {
        name: 'Greek Yogurt',
        portion_desc: '200 g',
        portion_grams: 200,
        calories: 130,
        protein: 15,
        carbs: 8,
        fat: 5,

      },
      {
        name: 'Mixed Berries',
        portion_desc: '100 g',
        portion_grams: 100,
        calories: 90,
        protein: 5,
        carbs: 17,
        fat: 1,

      }
    ]
  },
  {
    name: 'Salmon with Rice and Broccoli',
    kcal: 520,
    protein_g: 40,
    carb_g: 45,
    fat_g: 18,

    source: 'scan',
    imageIndex: 3,
    ingredients: [
      {
        name: 'Grilled Salmon',
        portion_desc: '150 g',
        portion_grams: 150,
        calories: 280,
        protein: 25,
        carbs: 0,
        fat: 12,

      },
      {
        name: 'Brown Rice',
        portion_desc: '100 g cooked',
        portion_grams: 100,
        calories: 120,
        protein: 3,
        carbs: 25,
        fat: 1,

      },
      {
        name: 'Steamed Broccoli',
        portion_desc: '150 g',
        portion_grams: 150,
        calories: 120,
        protein: 12,
        carbs: 20,
        fat: 5,

      }
    ]
  },
  {
    name: 'Protein Smoothie',
    kcal: 320,
    protein_g: 25,
    carb_g: 35,
    fat_g: 8,

    source: 'scan',
    imageIndex: 4,
    ingredients: [
      {
        name: 'Protein Powder',
        portion_desc: '30 g',
        portion_grams: 30,
        calories: 120,
        protein: 20,
        carbs: 3,
        fat: 2,

      },
      {
        name: 'Banana',
        portion_desc: '1 medium',
        portion_grams: 120,
        calories: 105,
        protein: 1,
        carbs: 27,
        fat: 0,

      },
      {
        name: 'Almond Milk',
        portion_desc: '250 ml',
        portion_grams: 250,
        calories: 40,
        protein: 2,
        carbs: 2,
        fat: 3,

      },
      {
        name: 'Spinach',
        portion_desc: '30 g',
        portion_grams: 30,
        calories: 7,
        protein: 1,
        carbs: 1,
        fat: 0,

      },
      {
        name: 'Peanut Butter',
        portion_desc: '15 g',
        portion_grams: 15,
        calories: 48,
        protein: 1,
        carbs: 2,
        fat: 3,

      }
    ]
  }
];

// ---------- Helper functions ----------
async function downloadAndUploadImage(imageUrl, uid, mealName, index) {
  try {
    console.log(`📸 Downloading image for ${mealName}...`);
    
    // Download image
    const response = await fetch(imageUrl);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    
    const buffer = await response.buffer();
    
    // Create filename in the same format as your app
    const timestamp = Date.now() + index; // Add index to avoid conflicts
    const fileName = `meal_${uid}_${timestamp}.jpg`;
    
    // Upload to Firebase Storage
    const bucket = storage.bucket();
    const file = bucket.file(`meal_images/${fileName}`);
    
    await file.save(buffer, {
      metadata: {
        contentType: 'image/jpeg',
      },
    });
    
    // Make file publicly readable
    await file.makePublic();
    
    // Get download URL
    const downloadUrl = `https://storage.googleapis.com/${bucket.name}/meal_images/${fileName}`;
    
    console.log(`✅ Uploaded image for ${mealName}: ${fileName}`);
    return downloadUrl;
    
  } catch (error) {
    console.error(`❌ Failed to upload image for ${mealName}:`, error);
    return null;
  }
}

// ---------- Seeder ----------
async function seedTodayMealsWithStorage(uid) {
  console.log(`🍽️ Seeding today's meals with Firebase Storage images for user: ${uid}`);
  
  const today = new Date();
  const todayKey = today.toISOString().split('T')[0]; // YYYY-MM-DD format
  console.log(`📅 Today's date key: ${todayKey}`);

  // Clear existing entries for today first
  const existingQuery = await db.collection('food_log_entries')
    .where('uid', '==', uid)
    .where('date', '==', todayKey)
    .get();

  if (!existingQuery.empty) {
    console.log(`🧹 Clearing ${existingQuery.docs.length} existing entries for today...`);
    const batch = db.batch();
    existingQuery.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    await batch.commit();
  }

  // Upload images and create meals
  const batch = db.batch();
  let mealCount = 0;

  for (const meal of sampleMeals) {
    console.log(`\n🍽️ Processing meal ${mealCount + 1}: ${meal.name}`);
    
    // Upload image to Firebase Storage
    const imageUrl = await downloadAndUploadImage(
      sampleImageUrls[meal.imageIndex], 
      uid, 
      meal.name, 
      mealCount
    );
    
    const ref = db.collection('food_log_entries').doc();
    const mealData = {
      uid,
      date: todayKey,
      name: meal.name,
      kcal: meal.kcal,
      protein_g: meal.protein_g,
      carb_g: meal.carb_g,
      fat_g: meal.fat_g,
      ingredients: meal.ingredients,
      source: meal.source,
      created_at: new Date(today.getTime() + (mealCount * 60 * 60 * 1000)) // Space meals 1 hour apart
    };
    
    // Only add image_url if upload was successful
    if (imageUrl) {
      mealData.image_url = imageUrl;
    }

    batch.set(ref, mealData);
    mealCount++;
    console.log(`✅ Queued: ${meal.name} (${meal.kcal} kcal) ${imageUrl ? 'with image' : 'without image'}`);
  }

  await batch.commit();
  console.log(`\n🎉 Added ${mealCount} sample meals for today!`);

  // Calculate totals
  const totalCalories = sampleMeals.reduce((sum, meal) => sum + meal.kcal, 0);
  const totalProtein = sampleMeals.reduce((sum, meal) => sum + meal.protein_g, 0);
  const totalCarbs = sampleMeals.reduce((sum, meal) => sum + meal.carb_g, 0);
  const totalFat = sampleMeals.reduce((sum, meal) => sum + meal.fat_g, 0);

  console.log(`\n📊 Today's totals:`);
  console.log(`🔥 Calories: ${totalCalories} kcal`);
  console.log(`🥩 Protein: ${totalProtein}g`);
  console.log(`🌾 Carbs: ${totalCarbs}g`);
  console.log(`🥑 Fat: ${totalFat}g`);
  console.log(`📸 Images uploaded to Firebase Storage!`);
}

// ---------- Main ----------
async function main() {
  const uid = 'iCqnjbHxKfZgT4Rx9Jg9LUge2cQ2'; // Your user ID
  
  try {
    console.log('🚀 Starting today\'s meal seeding with Firebase Storage...\n');
    await seedTodayMealsWithStorage(uid);
    console.log('\n🎉 Seeding completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during seeding:', error);
    process.exit(1);
  }
}

// Run the script
main();
