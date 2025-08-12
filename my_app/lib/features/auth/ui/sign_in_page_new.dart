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
  Widget build(BuildContext context) {
    return Scaffold(
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
                  final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
                  if (googleUser == null) return; // User cancelled
                  
                  final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
                  
                  final credential = GoogleAuthProvider.credential(
                    accessToken: googleAuth.accessToken,
                    idToken: googleAuth.idToken,
                  );
                  
                  await FirebaseAuth.instance.signInWithCredential(credential);
                  
                  if (!mounted) return;
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 300),
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
    // Use string-based units like settings page
    String units = _units == UnitSystem.metric ? 'metric' : 'imperial';
    String sex = _sex == Sex.male ? 'male' : 'female';
    int age = _age;
    double heightCm = _heightCm;
    double weightKg = _weightKg;
    String activity = _activityToString(_activity);
    String goal = _goalToString(_goal);
    double targetWeightKg = _targetWeightKg;
    double rateKgPerWeekMag = _rateKgPerWeek.abs();

    // Unit helpers (from settings page)
    double kgToDisplay(double kg) => units == 'metric' ? kg : kg * 2.2046226218;
    double displayToKg(double v) => units == 'metric' ? v : v / 2.2046226218;

    // Controllers for fields that need to update on unit toggle
    final weightCtrl = TextEditingController(text: kgToDisplay(weightKg).toStringAsFixed(1));
    final targetCtrl = TextEditingController(text: kgToDisplay(targetWeightKg).toStringAsFixed(1));

    // Height initial values for imperial
    final heightFtInit = (heightCm / 2.54 ~/ 12).toString();
    final heightInInit = ((heightCm / 2.54) % 12).toStringAsFixed(0);

    // Sync goal from target vs current (from settings page)
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

    // Flip goal and preserve absolute difference (from settings page)
    void flipGoalPreserveDiffAndRefreshControllers(void Function(void Function()) setLocal) {
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
        // Convert visible numbers on unit toggle (from settings page)
        void switchUnits(String newUnits) {
          if (newUnits == units) return;
          units = newUnits;
          weightCtrl.text = kgToDisplay(weightKg).toStringAsFixed(1);
          targetCtrl.text = kgToDisplay(targetWeightKg).toStringAsFixed(1);
          setLocal(() {});
        }

        // Slider value (display) is derived from positive magnitude (from settings page)
        final speedDisplay = units == 'metric' ? rateKgPerWeekMag : rateKgPerWeekMag * 2.2046226218;
        final speedMin = 0.0;
        final speedMax = (units == 'metric' ? 1.5 : 1.5 * 2.2046226218);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _profileFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Step 2 of 3', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                
                // Units (from settings page)
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

                // Sex & Age (from settings page)
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
                        decoration: const InputDecoration(labelText: 'Age (years)'),
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

                // Height (from settings page)
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
                          decoration: const InputDecoration(labelText: 'Height (ft)'),
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
                          decoration: const InputDecoration(labelText: 'Height (in)'),
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

                // Current weight (from settings page - uses controller)
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
                      syncGoalFromTarget(); // auto-adjust goal
                      setLocal(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Activity (from settings page)
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

                // Goal dropdown (from settings page - flips target and preserves diff)
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

                // Target weight (from settings page - uses controller)
                TextFormField(
                  controller: targetCtrl,
                  decoration: InputDecoration(
                    labelText: 'Target weight (${units == 'metric' ? 'kg' : 'lb'})',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) {
                      targetWeightKg = displayToKg(n);
                      syncGoalFromTarget(); // goal adjusts to match new relationship
                      setLocal(() {});
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Speed (from settings page - positive-only slider)
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

                // Navigation buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pageController.animateToPage(0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          // Update the main state with the local state values
                          setState(() {
                            _units = units == 'metric' ? UnitSystem.metric : UnitSystem.imperial;
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
                          
                          _pageController.animateToPage(2,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut);
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
                child: OutlinedButton(
                  onPressed: () => _pageController.animateToPage(1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut),
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

                      // Save to Firestore
                      final payload = {
                        'units': _units.name,
                        'sex': _sex.name,
                        'age': _age,
                        'height_cm': _heightCm,
                        'weight_kg': _weightKg,
                        'activity': _activity.name,
                        'goal': _goal.name,
                        'target_weight_kg': _targetWeightKg,
                        'rate_kg_per_week': _rateKgPerWeek,
                        'created_at': FieldValue.serverTimestamp(),
                      };

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .set(payload);

                      if (!mounted) return;
                      
                      // Navigate to main app
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                            builder: (context) => const MainNavPage()),
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
