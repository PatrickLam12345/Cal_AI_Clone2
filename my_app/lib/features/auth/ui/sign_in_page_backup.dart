import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../nav/ui/main_nav_page.dart';

enum UnitSystem { metric, imperial }

enum Sex { male, female }

enum ActivityLevel { sedentary, light, moderate, active, veryActive }

enum Goal { lose, maintain, gain }

class ProfilePayload {
  final UnitSystem units;
  final Sex sex;
  final int age; // years
  final double heightCm; // stored as cm internally
  final double weightKg; // stored as kg internally
  final ActivityLevel activity;
  final Goal goal;
  final double targetWeightKg; // kg
  /// Rate in kg/week (negative for loss, positive for gain)
  final double ratePerWeekKg;

  ProfilePayload({
    required this.units,
    required this.sex,
    required this.age,
    required this.heightCm,
    required this.weightKg,
    required this.activity,
    required this.goal,
    required this.targetWeightKg,
    required this.ratePerWeekKg,
  });
}

class SignupFlowPage extends StatefulWidget {
  final int startAtStep; // 0 = auth, 1 = profile, 2 = review
  const SignupFlowPage({super.key, this.startAtStep = 0});

  @override
  State<SignupFlowPage> createState() => _SignupFlowPageState();
}

class _SignupFlowPageState extends State<SignupFlowPage> {
  final _pageController = PageController();

  // Step 1 (Auth) - Google Sign-In only

  // Step 2 (Profile)
  final _profileFormKey = GlobalKey<FormState>();

  UnitSystem _units = UnitSystem.metric;
  Sex _sex = Sex.male;
  int _age = 22;

  // Internal storage uses metric; expose conversions for UI when imperial.
  double _heightCm = 175; // default 175cm
  double _weightKg = 70; // default 70kg
  ActivityLevel _activity = ActivityLevel.moderate;
  Goal _goal = Goal.maintain;
  double _targetWeightKg = 70; // same as starting by default

  // Rate slider: default 0 kg/week. Range -1.5 .. +1.5 kg/week (~ -3.3 .. +3.3 lb/wk)
  double _rateKgPerWeek = 0.0;

  // Helpers for imperial conversions
  double get _heightInches => _heightCm / 2.54;
  double get _weightLbs => _weightKg * 2.2046226218;
  set _heightInches(double v) => _heightCm = v * 2.54;
  set _weightLbs(double v) => _weightKg = v / 2.2046226218;

  // Helper methods to convert between enum and string (for settings page compatibility)
  String _activityToString(ActivityLevel activity) {
    switch (activity) {
      case ActivityLevel.sedentary: return 'sedentary';
      case ActivityLevel.light: return 'light';
      case ActivityLevel.moderate: return 'moderate';
      case ActivityLevel.active: return 'active';
      case ActivityLevel.veryActive: return 'veryactive';
    }
  }

  ActivityLevel _stringToActivity(String activity) {
    switch (activity) {
      case 'sedentary': return ActivityLevel.sedentary;
      case 'light': return ActivityLevel.light;
      case 'moderate': return ActivityLevel.moderate;
      case 'active': return ActivityLevel.active;
      case 'veryactive': return ActivityLevel.veryActive;
      default: return ActivityLevel.moderate;
    }
  }

  String _goalToString(Goal goal) {
    switch (goal) {
      case Goal.lose: return 'lose';
      case Goal.maintain: return 'maintain';
      case Goal.gain: return 'gain';
    }
  }

  Goal _stringToGoal(String goal) {
    switch (goal) {
      case 'lose': return Goal.lose;
      case 'maintain': return Goal.maintain;
      case 'gain': return Goal.gain;
      default: return Goal.maintain;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your account')),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildAuthStep(context),
          _buildProfileStep(context),
          _buildReviewStep(context),
        ],
      ),
    );
  }

  Widget _buildAuthStep(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome to Pati',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Track your nutrition with AI-powered meal analysis',
            style: TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.login, size: 24),
              label: const Text(
                'Continue with Google',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                try {
                  final gsi = GoogleSignIn.instance;

                  // Optional: if you have a web/server client ID, pass it here
                  // await gsi.initialize(serverClientId: 'YOUR_WEB_CLIENT_ID');
                  await gsi.initialize(); // safe to call multiple times

                  // New API: authenticate() instead of signIn()
                  final account = await gsi.authenticate();
                  // Get tokens (v7 exposes idToken only)
                  final auth = await account.authentication;

                  if (auth.idToken == null) {
                    throw Exception('Google Sign-In returned no idToken');
                  }

                  final cred =
                      GoogleAuthProvider.credential(idToken: auth.idToken);
                  await FirebaseAuth.instance.signInWithCredential(cred);

                  if (!mounted) return;
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Google Sign-In failed: $e')));
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Step 1 of 3',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep(BuildContext context) {
    final isMetric = _units == UnitSystem.metric;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _profileFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Step 2 of 3',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Units'),
                SegmentedButton<UnitSystem>(
                  segments: const [
                    ButtonSegment(
                        value: UnitSystem.metric, label: Text('Metric')),
                    ButtonSegment(
                        value: UnitSystem.imperial, label: Text('Imperial')),
                  ],
                  selected: <UnitSystem>{_units},
                  onSelectionChanged: (s) => setState(() => _units = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<Sex>(
                    value: _sex,
                    decoration: const InputDecoration(labelText: 'Sex'),
                    items: const [
                      DropdownMenuItem(value: Sex.male, child: Text('Male')),
                      DropdownMenuItem(value: Sex.female, child: Text('Female')),
                    ],
                    onChanged: (v) => setState(() => _sex = v ?? Sex.male),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _age.toString(),
                    decoration: const InputDecoration(labelText: 'Age (years)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = int.tryParse(v);
                      if (n != null) setState(() => _age = n.clamp(10, 100));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Height
            if (isMetric)
              TextFormField(
                initialValue: _heightCm.toStringAsFixed(0),
                decoration: const InputDecoration(labelText: 'Height (cm)'),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = double.tryParse(v);
                  if (n != null) setState(() => _heightCm = n.clamp(120, 250));
                },
              )
            else
              Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: (_heightInches ~/ 12).toString(),
                    decoration: const InputDecoration(labelText: 'Height (ft)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final ft = int.tryParse(v) ?? 0;
                      final inches = _heightCm / 2.54 % 12;
                      setState(() => _heightCm = (ft * 12 + inches) * 2.54);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: (_heightInches % 12).toStringAsFixed(0),
                    decoration: const InputDecoration(labelText: 'Height (in)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final inch = double.tryParse(v) ?? 0;
                      final ft = _heightCm / 2.54 ~/ 12;
                      setState(() => _heightCm = (ft * 12 + inch) * 2.54);
                    },
                  ),
                ),
              ]),
            const SizedBox(height: 12),
            // Weight
            TextFormField(
              initialValue: isMetric
                  ? _weightKg.toStringAsFixed(1)
                  : _weightLbs.toStringAsFixed(1),
              decoration: InputDecoration(
                  labelText: 'Weight (${isMetric ? 'kg' : 'lb'})'),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = double.tryParse(v);
                if (n != null) {
                  setState(() {
                    if (isMetric) {
                      _weightKg = n.clamp(30, 350);
                    } else {
                      _weightLbs = n.clamp(66, 770);
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ActivityLevel>(
              value: _activity,
              decoration: const InputDecoration(labelText: 'Activity level'),
              items: const [
                DropdownMenuItem(
                    value: ActivityLevel.sedentary, child: Text('Sedentary')),
                DropdownMenuItem(
                    value: ActivityLevel.light, child: Text('Light')),
                DropdownMenuItem(
                    value: ActivityLevel.moderate, child: Text('Moderate')),
                DropdownMenuItem(
                    value: ActivityLevel.active, child: Text('Active')),
                DropdownMenuItem(
                    value: ActivityLevel.veryActive,
                    child: Text('Very active')),
              ],
              onChanged: (v) =>
                  setState(() => _activity = v ?? ActivityLevel.moderate),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Goal>(
              value: _goal,
              decoration: const InputDecoration(labelText: 'Goal'),
              items: const [
                DropdownMenuItem(value: Goal.lose, child: Text('Lose weight')),
                DropdownMenuItem(value: Goal.maintain, child: Text('Maintain')),
                DropdownMenuItem(value: Goal.gain, child: Text('Gain weight')),
              ],
              onChanged: (v) => setState(() => _goal = v ?? Goal.maintain),
            ),
            const SizedBox(height: 12),
            // Target weight
            TextFormField(
              initialValue:
                  (isMetric ? _targetWeightKg : _targetWeightKg * 2.2046226218)
                      .toStringAsFixed(1),
              decoration: InputDecoration(
                  labelText: 'Target weight (${isMetric ? 'kg' : 'lb'})'),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final n = double.tryParse(v);
                if (n != null) {
                  setState(() {
                    _targetWeightKg = isMetric ? n : (n / 2.2046226218);
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Text('Speed (${_rateLabel()})', style: textTheme.titleMedium),
            Slider(
              value: _rateKgPerWeek,
              min: -1.5,
              max: 1.5,
              divisions: 12, // 0.25 kg/wk increments
              label: _rateLabel(),
              onChanged: (v) => setState(
                  () => _rateKgPerWeek = double.parse(v.toStringAsFixed(2))),
            ),
            Text(
              'Tip: -0.25 to -0.75 kg/week is a moderate loss. +0.25 to +0.5 kg/week is a lean bulk.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (!_profileFormKey.currentState!.validate()) return;
                      _pageController.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut);
                    },
                    child: const Text('Review'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _rateLabel() {
    final arrow = _rateKgPerWeek > 0
        ? 'gain'
        : (_rateKgPerWeek < 0 ? 'loss' : 'maintain');

    if (_units == UnitSystem.metric) {
      return '${_rateKgPerWeek.toStringAsFixed(2)} kg/week • $arrow';
    } else {
      final lbsPerWeek = _rateKgPerWeek * 2.2046226218;
      return '${lbsPerWeek.toStringAsFixed(2)} lb/week • $arrow';
    }
  }

  Widget _buildReviewStep(BuildContext context) {
    final isMetric = _units == UnitSystem.metric;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 3 of 3',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Account', FirebaseAuth.instance.currentUser?.email ?? 'Google Account'),
                  _kv('Units', isMetric ? 'Metric' : 'Imperial'),
                  _kv('Sex', _sex.name),
                  _kv('Age', '$_age'),
                  _kv(
                      'Height',
                      isMetric
                          ? '${_heightCm.toStringAsFixed(0)} cm'
                          : '${(_heightInches ~/ 12)} ft ${(_heightInches % 12).toStringAsFixed(0)} in'),
                  _kv(
                      'Weight',
                      isMetric
                          ? '${_weightKg.toStringAsFixed(1)} kg'
                          : '${(_weightKg * 2.2046226218).toStringAsFixed(1)} lb'),
                  _kv('Activity', _activity.name),
                  _kv('Goal', _goal.name),
                  _kv(
                      'Target weight',
                      isMetric
                          ? '${_targetWeightKg.toStringAsFixed(1)} kg'
                          : '${(_targetWeightKg * 2.2046226218).toStringAsFixed(1)} lb'),
                  _kv('Speed', _rateLabel()),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        throw Exception('No authenticated user found');
                      }

                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      final payload = ProfilePayload(
                        units: _units,
                        sex: _sex,
                        age: _age,
                        heightCm: _heightCm,
                        weightKg: _weightKg,
                        activity: _activity,
                        goal: _goal,
                        targetWeightKg: _targetWeightKg,
                        ratePerWeekKg: _rateKgPerWeek,
                      );

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .set({
                        'email': FirebaseAuth.instance.currentUser!.email,
                        'units': payload.units.name,
                        'sex': payload.sex.name,
                        'age': payload.age,
                        'height_cm': payload.heightCm,
                        'weight_kg': payload.weightKg,
                        'activity': payload.activity.name,
                        'goal': payload.goal.name,
                        'target_weight_kg': payload.targetWeightKg,
                        'rate_kg_per_week': payload.ratePerWeekKg,
                          // Defaults for macro preferences; user can change in Settings
                          'protein_g_per_kg': payload.goal == Goal.lose ? 2.2 : (payload.goal == Goal.gain ? 1.6 : 1.8),
                          'fat_percent': 25,
                        'created_at': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                      if (!context.mounted) return;
                  
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const MainNavPage()),
                        (route) => false,
                      );
                    } on FirebaseAuthException catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Auth error: ${e.code}')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  },
                  child: const Text('Create account'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontWeight: FontWeight.w500)),
            Flexible(child: Text(v, textAlign: TextAlign.right)),
          ],
        ),
      );
}
