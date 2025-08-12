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
  final int age;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activity;
  final Goal goal;
  final double targetWeightKg;
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

  // ---- Step 2 (Profile) state (internal = metric) ----
  final _profileFormKey = GlobalKey<FormState>();
  UnitSystem _units = UnitSystem.metric;
  Sex _sex = Sex.male;
  int _age = 22;
  double _heightCm = 175;
  double _weightKg = 70;
  ActivityLevel _activity = ActivityLevel.moderate;
  Goal _goal = Goal.maintain;
  double _targetWeightKg = 70;
  double _rateKgPerWeek = 0.0; // negative lose, positive gain

  // Helpers (same as Settings)
  double get _heightInches => _heightCm / 2.54;
  double get _weightLbs => _weightKg * 2.2046226218;
  set _heightInches(double v) => _heightCm = v * 2.54;
  set _weightLbs(double v) => _weightKg = v / 2.2046226218;

  // ---- enum<->string helpers (match Settings page storage) ----
  String _activityToString(ActivityLevel a) {
    switch (a) {
      case ActivityLevel.sedentary:
        return 'sedentary';
      case ActivityLevel.light:
        return 'light';
      case ActivityLevel.moderate:
        return 'moderate';
      case ActivityLevel.active:
        return 'active';
      case ActivityLevel.veryActive:
        return 'veryactive'; // IMPORTANT: match Settings' lowercase
    }
  }

  ActivityLevel _stringToActivity(String s) {
    switch (s) {
      case 'sedentary':
        return ActivityLevel.sedentary;
      case 'light':
        return ActivityLevel.light;
      case 'moderate':
        return ActivityLevel.moderate;
      case 'active':
        return ActivityLevel.active;
      case 'veryactive':
        return ActivityLevel.veryActive;
      default:
        return ActivityLevel.moderate;
    }
  }

  String _goalToString(Goal g) {
    switch (g) {
      case Goal.lose:
        return 'lose';
      case Goal.maintain:
        return 'maintain';
      case Goal.gain:
        return 'gain';
    }
  }

  Goal _stringToGoal(String s) {
    switch (s) {
      case 'lose':
        return Goal.lose;
      case 'maintain':
        return Goal.maintain;
      case 'gain':
        return Goal.gain;
      default:
        return Goal.maintain;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.startAtStep > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.animateToPage(
          widget.startAtStep,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      });
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
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildAuthStep(context),
          _buildProfileStep(context), // <-- units→speed copied from Settings
          _buildReviewStep(context),
        ],
      ),
    );
  }

  // ---------------- Step 1: Auth ----------------
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
            style: TextStyle(fontSize: 16),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              onPressed: () async {
                try {
                  final gsi = GoogleSignIn.instance;
                  await gsi.initialize();
                  final account = await gsi.authenticate();
                  final auth = await account.authentication;
                  if (auth.idToken == null) {
                    throw Exception('Google Sign-In returned no idToken');
                  }
                  final cred =
                      GoogleAuthProvider.credential(idToken: auth.idToken);
                  await FirebaseAuth.instance.signInWithCredential(cred);

                  if (!mounted) return;
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Google Sign-In failed: $e')),
                  );
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

  // ---------------- Step 2: Profile (copied logic) ----------------
  Widget _buildProfileStep(BuildContext context) {
    // Local working copies (string-based like Settings dialog)
    String units = _units == UnitSystem.metric ? 'metric' : 'imperial';
    String sex = _sex == Sex.male ? 'male' : 'female';
    int age = _age;
    double heightCm = _heightCm;
    double weightKg = _weightKg;
    String activity = _activityToString(_activity);
    String goal = _goalToString(_goal);
    double targetWeightKg = _targetWeightKg;
    double rateKgPerWeekMag = _rateKgPerWeek.abs(); // POSITIVE magnitude

    // Unit helpers (identical to Settings)
    double kgToDisplay(double kg) => units == 'metric' ? kg : kg * 2.2046226218;
    double displayToKg(double v) => units == 'metric' ? v : v / 2.2046226218;

    // Controllers (so fields refresh on unit toggle)
    final weightCtrl =
        TextEditingController(text: kgToDisplay(weightKg).toStringAsFixed(1));
    final targetCtrl = TextEditingController(
        text: kgToDisplay(targetWeightKg).toStringAsFixed(1));

    // Height initial values (imperial)
    final heightFtInit = (heightCm / 2.54 ~/ 12).toString();
    final heightInInit = ((heightCm / 2.54) % 12).toStringAsFixed(0);

    // Keep goal synced with target vs current
    void syncGoalFromTarget() {
      final diff = targetWeightKg - weightKg;
      if (diff.abs() < 1e-6) {
        goal = 'maintain';
      } else if (diff > 0) {
        goal = 'gain';
      } else {
        goal = 'lose';
      }
    }

    // Flip goal and preserve absolute difference (and refresh controllers)
    void flipGoalPreserveDiffAndRefreshControllers(
        void Function(void Function()) setLocal) {
      final diffAbs = (targetWeightKg - weightKg).abs();
      if (goal == 'gain') {
        targetWeightKg = weightKg + diffAbs;
      } else if (goal == 'lose') {
        targetWeightKg = weightKg - diffAbs;
      } else {
        targetWeightKg = weightKg;
      }
      targetCtrl.text = kgToDisplay(targetWeightKg).toStringAsFixed(1);
      syncGoalFromTarget();
      setLocal(() {});
    }

    return StatefulBuilder(
      builder: (context, setLocal) {
        // Switch units (re-write controller text; internal stays kg/cm)
        void switchUnits(String newUnits) {
          if (newUnits == units) return;
          units = newUnits;
          weightCtrl.text = kgToDisplay(weightKg).toStringAsFixed(1);
          targetCtrl.text = kgToDisplay(targetWeightKg).toStringAsFixed(1);
          setLocal(() {});
        }

        // Speed slider (positive-only display; sign applied on save)
        final speedDisplay =
            units == 'metric' ? rateKgPerWeekMag : rateKgPerWeekMag * 2.2046226218;
        final speedMin = 0.0;
        final speedMax = (units == 'metric' ? 1.5 : 1.5 * 2.2046226218);

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

                // Units
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Units'),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'metric', label: Text('Metric')),
                        ButtonSegment(value: 'imperial', label: Text('Imperial')),
                      ],
                      selected: {units},
                      onSelectionChanged: (s) => switchUnits(s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sex & Age
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: sex,
                        decoration: const InputDecoration(labelText: 'Sex'),
                        items: const [
                          DropdownMenuItem(value: 'male', child: Text('Male')),
                          DropdownMenuItem(value: 'female', child: Text('Female')),
                        ],
                        onChanged: (v) => setLocal(() => sex = v ?? 'male'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: age.toString(),
                        decoration:
                            const InputDecoration(labelText: 'Age (years)'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null) setLocal(() => age = n.clamp(10, 100));
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Height
                if (units == 'metric')
                  TextFormField(
                    initialValue: heightCm.toStringAsFixed(0),
                    decoration: const InputDecoration(labelText: 'Height (cm)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      final n = double.tryParse(v);
                      if (n != null) setLocal(() => heightCm = n.clamp(120, 250));
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: heightFtInit,
                          decoration:
                              const InputDecoration(labelText: 'Height (ft)'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final ft = int.tryParse(v) ?? 0;
                            final inches = heightCm / 2.54 % 12;
                            setLocal(() => heightCm = (ft * 12 + inches) * 2.54);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: heightInInit,
                          decoration:
                              const InputDecoration(labelText: 'Height (in)'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final inch = double.tryParse(v) ?? 0;
                            final ft = heightCm / 2.54 ~/ 12;
                            setLocal(() => heightCm = (ft * 12 + inch) * 2.54);
                          },
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),

                // Weight
                TextFormField(
                  controller: weightCtrl,
                  decoration: InputDecoration(
                    labelText: 'Weight (${units == 'metric' ? 'kg' : 'lb'})',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) {
                      weightKg = displayToKg(n);
                      syncGoalFromTarget();
                      setLocal(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Activity
                DropdownButtonFormField<String>(
                  value: activity,
                  decoration: const InputDecoration(labelText: 'Activity level'),
                  items: const [
                    DropdownMenuItem(value: 'sedentary', child: Text('Sedentary')),
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                    DropdownMenuItem(value: 'moderate', child: Text('Moderate')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'veryactive', child: Text('Very active')),
                  ],
                  onChanged: (v) => setLocal(() => activity = v ?? 'moderate'),
                ),
                const SizedBox(height: 12),

                // Goal (flip preserves diff)
                DropdownButtonFormField<String>(
                  value: goal,
                  decoration: const InputDecoration(labelText: 'Goal'),
                  items: const [
                    DropdownMenuItem(value: 'lose', child: Text('Lose weight')),
                    DropdownMenuItem(value: 'maintain', child: Text('Maintain')),
                    DropdownMenuItem(value: 'gain', child: Text('Gain weight')),
                  ],
                  onChanged: (v) {
                    if (v == null || v == goal) return;
                    goal = v;
                    flipGoalPreserveDiffAndRefreshControllers(setLocal);
                  },
                ),
                const SizedBox(height: 12),

                // Target weight
                TextFormField(
                  controller: targetCtrl,
                  decoration: InputDecoration(
                    labelText:
                        'Target weight (${units == 'metric' ? 'kg' : 'lb'})',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) {
                      targetWeightKg = displayToKg(n);
                      syncGoalFromTarget();
                      setLocal(() {});
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Speed (positive-only; sign applied on save)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Speed (${units == 'metric' ? 'kg/wk' : 'lb/wk'})'),
                    Text(speedDisplay.toStringAsFixed(2)),
                  ],
                ),
                Slider(
                  value: speedDisplay,
                  min: speedMin,
                  max: speedMax,
                  divisions: 30,
                  onChanged: (v) {
                    rateKgPerWeekMag = displayToKg(v).clamp(0.0, 1.5);
                    setLocal(() {});
                  },
                ),
                const SizedBox(height: 16),

                // Nav
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pageController.animateToPage(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          // Commit local -> main state
                          setState(() {
                            _units = units == 'metric'
                                ? UnitSystem.metric
                                : UnitSystem.imperial;
                            _sex = sex == 'male' ? Sex.male : Sex.female;
                            _age = age;
                            _heightCm = heightCm;
                            _weightKg = weightKg;
                            _activity = _stringToActivity(activity);
                            _goal = _stringToGoal(goal);
                            _targetWeightKg = targetWeightKg;
                            _rateKgPerWeek = switch (goal) {
                              'lose' => -rateKgPerWeekMag,
                              'gain' => rateKgPerWeekMag,
                              _ => 0.0,
                            };
                          });

                          _pageController.animateToPage(
                            2,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- Step 3: Review + Save ----------------
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
                  _kv('Account',
                      FirebaseAuth.instance.currentUser?.email ?? 'Google Account'),
                  _kv('Units', isMetric ? 'Metric' : 'Imperial'),
                  _kv('Sex', _sex.name),
                  _kv('Age', '$_age'),
                  _kv(
                    'Height',
                    isMetric
                        ? '${_heightCm.toStringAsFixed(0)} cm'
                        : '${(_heightInches ~/ 12)} ft ${(_heightInches % 12).toStringAsFixed(0)} in',
                  ),
                  _kv(
                    'Weight',
                    isMetric
                        ? '${_weightKg.toStringAsFixed(1)} kg'
                        : '${(_weightKg * 2.2046226218).toStringAsFixed(1)} lb',
                  ),
                  _kv('Activity', _activityToString(_activity)),
                  _kv('Goal', _goalToString(_goal)),
                  _kv(
                    'Target weight',
                    isMetric
                        ? '${_targetWeightKg.toStringAsFixed(1)} kg'
                        : '${(_targetWeightKg * 2.2046226218).toStringAsFixed(1)} lb',
                  ),
                  _kv('Speed', _rateLabel()),
                ],
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    try {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        throw Exception('No authenticated user found');
                      }

                      // IMPORTANT: match Settings page keys/format
                      final payload = {
                        'units': _units.name, // 'metric' | 'imperial'
                        'sex': _sex.name, // 'male' | 'female'
                        'age': _age,
                        'height_cm': _heightCm,
                        'weight_kg': _weightKg,
                        'activity': _activityToString(_activity), // 'veryactive'
                        'goal': _goalToString(_goal), // 'lose'|'maintain'|'gain'
                        'target_weight_kg': _targetWeightKg,
                        'rate_kg_per_week': _rateKgPerWeek,
                        'created_at': FieldValue.serverTimestamp(),
                      };

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set(payload, SetOptions(merge: true));

                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (context) => const MainNavPage(),
                        ),
                        (route) => false,
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Setup failed: $e')),
                      );
                    }
                  },
                  child: const Text('Complete Setup'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
