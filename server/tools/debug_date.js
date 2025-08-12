// server/tools/debug_date.js

// Check different date formatting methods
const now = new Date();

console.log('🕐 Current time (raw):', now);
console.log('🌍 UTC ISO string:', now.toISOString());
console.log('📅 ISO date only:', now.toISOString().split('T')[0]);
console.log('🗓️ Local date string:', now.toDateString());
console.log('📆 Local YYYY-MM-DD:', 
  now.getFullYear() + '-' + 
  String(now.getMonth() + 1).padStart(2, '0') + '-' + 
  String(now.getDate()).padStart(2, '0')
);

console.log('\n⏰ Timezone info:');
console.log('UTC offset minutes:', now.getTimezoneOffset());
console.log('Local timezone (approx):', -now.getTimezoneOffset() / 60);

console.log('\n🔍 What different systems might see:');
console.log('Server UTC date:', now.toISOString().split('T')[0]);

// Simulate what a Flutter app in different timezones might see
const localDate = new Date(now.getTime() - (now.getTimezoneOffset() * 60000));
console.log('Flutter local date:', localDate.toISOString().split('T')[0]);

// Check what happens if we're close to midnight
console.log('\n🕛 Midnight scenarios:');
const earlyMorning = new Date();
earlyMorning.setHours(1, 0, 0, 0);  // 1 AM local
console.log('1 AM local UTC:', earlyMorning.toISOString().split('T')[0]);

const lateMorning = new Date();
lateMorning.setHours(23, 0, 0, 0);  // 11 PM local  
console.log('11 PM local UTC:', lateMorning.toISOString().split('T')[0]);
