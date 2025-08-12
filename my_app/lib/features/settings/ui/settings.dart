import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // ----- Local editable state -----
  String _units = 'metric';
  String _sex = 'male';
  int _age = 22;
  double _heightCm = 175;
  double _weightKg = 70;
  String _activity = 'moderate';
  String _goal = 'maintain';
  double _targetWeightKg = 70;
  double _rateKgPerWeek = 0.0; // always stored as kg/week internally

  // Preferences for macro calc
  double _proteinGPerKg = 1.8; // protein grams per kg bodyweight (internal)
  double _fatPercent = 25; // % of calories from fat

  // Macro targets
  double _calorieGoal = 2000;
  double _proteinGoalG = 150;
  double _carbGoalG = 200;
  double _fatGoalG = 70;

  // Slider limits
  static const double _minCalories = 800;
  static const double _maxCalories = 7000;
  static const int _calorieDivisions =
      ((_maxCalories - _minCalories) ~/ 10); // 10-Cal steps
  static const double _maxCarbG = 1000;

  // Derived unit helpers
  double get _heightInches => _heightCm / 2.54;
  double get _weightLbs => _weightKg * 2.2046226218;
  set _heightInches(double v) => _heightCm = v * 2.54;
  set _weightLbs(double v) => _weightKg = v / 2.2046226218;

  // Firestore
  DocumentReference<Map<String, dynamic>>? _docRef;
  late Future<void> _init;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      _init = _loadInitial();
    } else {
      _init = Future.value();
    }
  }

  Future<void> _loadInitial() async {
    final ref = _docRef;
    if (ref == null) return;
    final snap = await ref.get();
    if (snap.exists) {
      final data = snap.data()!;
      _hydrateFromDoc(data);
    }
  }

  // sign helper (since double.sign doesn't exist)
  int _sgn(double x) => x == 0 ? 0 : (x > 0 ? 1 : -1);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<void>(
        future: _init,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.flag),
                title: const Text('Edit Goals & Details'),
                subtitle: const Text(
                    'Age, sex, height, weight, activity, goal, speed…'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openGoalsDialog,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.restaurant),
                title: const Text('Adjust Macros'),
                subtitle: Text(
                  '${_calorieGoal.round()} Cal • P ${_proteinGoalG.round()} / C ${_carbGoalG.round()} / F ${_fatGoalG.round()} g',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openMacrosDialog,
              ),
              const SizedBox(height: 24),

              // ===== Account section =====
              ExpansionTile(
                key: const PageStorageKey('settings_account'),
                maintainState: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                title: const Text('Account'),
                childrenPadding: const EdgeInsets.all(12),
                children: [
                  FilledButton.tonal(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Signed out')),
                      );
                    },
                    child: const Text('Log out'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete account?'),
                          content: const Text(
                              'This will permanently delete your account and data.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;

                      try {
                        final user = FirebaseAuth.instance.currentUser!;
                        final uid = user.uid;
                        await _docRef!.delete();
                        final entries = await FirebaseFirestore.instance
                            .collection('diary_entries')
                            .where('uid', isEqualTo: uid)
                            .limit(200)
                            .get();
                        for (final d in entries.docs) {
                          await d.reference.delete();
                        }
                        await user.delete();
                      } on FirebaseAuthException catch (e) {
                        if (e.code == 'requires-recent-login') {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Recent login required to delete account. Please sign in again.'),
                            ),
                          );
                          return;
                        }
                        rethrow;
                      } finally {
                        await FirebaseAuth.instance.signOut();
                      }

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account deleted')),
                      );
                    },
                    child: const Text('Delete account'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ===================== DIALOGS =====================

  Future<void> _openGoalsDialog() async {
    // Local state copies
    String units = _units;
    String sex = _sex;
    int age = _age;
    double heightCm = _heightCm;
    double weightKg = _weightKg; // always kg internally
    String activity = _activity;
    String goal = _goal; // 'lose' | 'maintain' | 'gain'
    double targetWeightKg = _targetWeightKg; // always kg internally
    double rateKgPerWeekMag = _rateKgPerWeek.abs(); // POSITIVE ONLY magnitude
    double proteinGPerKg = _proteinGPerKg;
    double fatPercent = _fatPercent;

    // Unit helpers
    double kgToDisplay(double kg) => units == 'metric' ? kg : kg * 2.2046226218;
    double displayToKg(double v) => units == 'metric' ? v : v / 2.2046226218;

    // --- Controllers so fields actually refresh when we update values ---
    final weightCtrl =
        TextEditingController(text: kgToDisplay(weightKg).toStringAsFixed(1));
    final targetCtrl = TextEditingController(
        text: kgToDisplay(targetWeightKg).toStringAsFixed(1));

    // Height fields (these re-create when units branch changes, so no controller required)
    final heightFtInit = (heightCm / 2.54 ~/ 12).toString();
    final heightInInit = ((heightCm / 2.54) % 12).toStringAsFixed(0);

    // Sync goal from target vs current (no controller updates here)
    void _syncGoalFromTarget() {
      final diff = targetWeightKg - weightKg;
      if (diff.abs() < 1e-6) {
        goal = 'maintain';
      } else if (diff > 0) {
        goal = 'gain';
      } else {
        goal = 'lose';
      }
    }

    // Flip goal and preserve absolute difference by mirroring the target
    void _flipGoalPreserveDiffAndRefreshControllers(
        void Function(void Function()) setLocal) {
      final diffAbs = (targetWeightKg - weightKg).abs();
      if (goal == 'gain') {
        targetWeightKg = weightKg + diffAbs;
      } else if (goal == 'lose') {
        targetWeightKg = weightKg - diffAbs;
      } else {
        // maintain
        targetWeightKg = weightKg;
      }
      // refresh the target text field immediately
      targetCtrl.text = kgToDisplay(targetWeightKg).toStringAsFixed(1);
      // also make sure goal reflects the new relationship (should already)
      _syncGoalFromTarget();
      setLocal(() {}); // force rebuild for labels like speed text
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            // Convert visible numbers on unit toggle by rewriting controller text.
            void _switchUnits(String newUnits) {
              if (newUnits == units) return;
              units = newUnits;
              // Re-write controllers with converted display values (internal stays kg)
              weightCtrl.text = kgToDisplay(weightKg).toStringAsFixed(1);
              targetCtrl.text = kgToDisplay(targetWeightKg).toStringAsFixed(1);
              setLocal(() {});
            }

            // Slider value (display) is derived from positive magnitude
            final speedDisplay = units == 'metric'
                ? rateKgPerWeekMag
                : rateKgPerWeekMag * 2.2046226218;
            final speedMin = 0.0; // positive-only slider
            final speedMax = (units == 'metric' ? 1.5 : 1.5 * 2.2046226218);

            return AlertDialog(
              title: const Text('Edit Goals & Details'),
              content: SizedBox(
                width: 420, // fixed width so it doesn't reflow
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Units
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Units'),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'metric', label: Text('Metric')),
                              ButtonSegment(
                                  value: 'imperial', label: Text('Imperial')),
                            ],
                            selected: {units},
                            onSelectionChanged: (s) => _switchUnits(s.first),
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
                              decoration:
                                  const InputDecoration(labelText: 'Sex'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'male', child: Text('Male')),
                                DropdownMenuItem(
                                    value: 'female', child: Text('Female')),
                              ],
                              onChanged: (v) =>
                                  setLocal(() => sex = v ?? 'male'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: age.toString(),
                              decoration: const InputDecoration(
                                  labelText: 'Age (years)'),
                              keyboardType: TextInputType.number,
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null)
                                  setLocal(() => age = n.clamp(10, 100));
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
                          decoration:
                              const InputDecoration(labelText: 'Height (cm)'),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = double.tryParse(v);
                            if (n != null)
                              setLocal(() => heightCm = n.clamp(120, 250));
                          },
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: heightFtInit,
                                decoration: const InputDecoration(
                                    labelText: 'Height (ft)'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final ft = int.tryParse(v) ?? 0;
                                  final inches = heightCm / 2.54 % 12;
                                  setLocal(() =>
                                      heightCm = (ft * 12 + inches) * 2.54);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: heightInInit,
                                decoration: const InputDecoration(
                                    labelText: 'Height (in)'),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  final inch = double.tryParse(v) ?? 0;
                                  final ft = heightCm / 2.54 ~/ 12;
                                  setLocal(
                                      () => heightCm = (ft * 12 + inch) * 2.54);
                                },
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),

                      // Current weight (uses controller so it live-updates on unit toggle)
                      TextFormField(
                        controller: weightCtrl,
                        decoration: InputDecoration(
                          labelText:
                              'Weight (${units == 'metric' ? 'kg' : 'lb'})',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final n = double.tryParse(v);
                          if (n != null) {
                            weightKg = displayToKg(n);
                            // after current weight changes, re-evaluate goal vs target
                            _syncGoalFromTarget();
                            setLocal(() {}); // refresh goal label if needed
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Activity
                      DropdownButtonFormField<String>(
                        value: activity,
                        decoration:
                            const InputDecoration(labelText: 'Activity level'),
                        items: const [
                          DropdownMenuItem(
                              value: 'sedentary', child: Text('Sedentary')),
                          DropdownMenuItem(
                              value: 'light', child: Text('Light')),
                          DropdownMenuItem(
                              value: 'moderate', child: Text('Moderate')),
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'veryactive', child: Text('Very active')),
                        ],
                        onChanged: (v) =>
                            setLocal(() => activity = v ?? 'moderate'),
                      ),
                      const SizedBox(height: 12),

                      // Goal dropdown (flips target and preserves diff)
                      DropdownButtonFormField<String>(
                        value: goal,
                        decoration: const InputDecoration(labelText: 'Goal'),
                        items: const [
                          DropdownMenuItem(
                              value: 'lose', child: Text('Lose weight')),
                          DropdownMenuItem(
                              value: 'maintain', child: Text('Maintain')),
                          DropdownMenuItem(
                              value: 'gain', child: Text('Gain weight')),
                        ],
                        onChanged: (v) {
                          if (v == null || v == goal) return;
                          goal = v;
                          _flipGoalPreserveDiffAndRefreshControllers(setLocal);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Target weight (controller so it updates on flips/unit toggle)
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
                            _syncGoalFromTarget(); // goal adjusts to match new relationship
                            setLocal(() {}); // refresh goal label
                          }
                        },
                      ),
                      const SizedBox(height: 8),

                      // Speed (positive-only slider; goal decides sign on save)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              'Speed (${units == 'metric' ? 'kg/wk' : 'lb/wk'})'),
                          Text(speedDisplay.toStringAsFixed(2)),
                        ],
                      ),
                      Slider(
                        value: speedDisplay,
                        min: speedMin,
                        max: speedMax,
                        divisions: 30,
                        onChanged: (v) {
                          // store positive magnitude back in kg/week
                          rateKgPerWeekMag = displayToKg(v).clamp(0.0, 1.5);
                          setLocal(() {}); // refresh label
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    setState(() {
                      _units = units;
                      _sex = sex;
                      _age = age;
                      _heightCm = heightCm;
                      _weightKg = weightKg;
                      _activity = activity;
                      _goal = goal;
                      _targetWeightKg = targetWeightKg;
                      _rateKgPerWeek = switch (goal) {
                        'lose' => -rateKgPerWeekMag,
                        'gain' => rateKgPerWeekMag,
                        _ => 0.0,
                      };
                      _proteinGPerKg = proteinGPerKg;
                      _fatPercent = fatPercent;

                      _recomputeFromGoals(); // keep if you want macros to update automatically
                    });

                    final ref = _docRef;
                    if (ref != null) {
                      await ref.set({
                        'units': _units,
                        'sex': _sex,
                        'age': _age,
                        'height_cm': _heightCm,
                        'weight_kg': _weightKg,
                        'activity': _activity,
                        'goal': _goal,
                        'target_weight_kg': _targetWeightKg,
                        'rate_kg_per_week': _rateKgPerWeek,
                        'protein_g_per_kg': _proteinGPerKg,
                        'fat_percent': _fatPercent,
                        'calories_override': _calorieGoal,
                        'protein_g_override': _proteinGoalG,
                        'carb_g_override': _carbGoalG,
                        'fat_g_override': _fatGoalG,
                        'updated_at': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    }

                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Goals & details saved')),
                    );
                  },
                  child: const Text('Save changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openMacrosDialog() async {
    // Local copies
    double calorieGoal = _calorieGoal;
    double proteinG = _proteinGoalG;
    double carbG = _carbGoalG;
    double fatG = _fatGoalG;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setLocal) {
          double macroCals() => proteinG * 4 + carbG * 4 + fatG * 9;

          void syncCarbsToCalorieFill() {
            final pfCals = proteinG * 4 + fatG * 9;
            final allowedCarb = (calorieGoal - pfCals) / 4.0;
            carbG = allowedCarb.clamp(0, _maxCarbG).toDouble();
          }

          return AlertDialog(
            title: const Text('Adjust Macros'),
            content: SizedBox(
              width: 420, // fixed width to avoid reflow
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Calories'),
                          Text('${calorieGoal.round()} Cal'),
                        ]),
                    Slider(
                      value: calorieGoal
                          .clamp(_minCalories, _maxCalories)
                          .toDouble(),
                      min: _minCalories,
                      max: _maxCalories,
                      divisions: _calorieDivisions,
                      label: '${calorieGoal.round()} Cal',
                      onChanged: (v) => setLocal(() {
                        calorieGoal = v;
                        // Carbs fill to match Cal target
                        syncCarbsToCalorieFill();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Protein'),
                          Text('${proteinG.round()} g'),
                        ]),
                    Slider(
                      value: proteinG,
                      min: 50,
                      max: 400,
                      divisions: 350,
                      label: '${proteinG.round()} g',
                      onChanged: (v) => setLocal(() {
                        proteinG = v;
                        calorieGoal = macroCals()
                            .clamp(_minCalories, _maxCalories)
                            .toDouble();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Carbs'),
                          Text('${carbG.round()} g'),
                        ]),
                    Slider(
                      value: carbG.clamp(0, _maxCarbG).toDouble(),
                      min: 0,
                      max: _maxCarbG,
                      divisions: _maxCarbG.toInt(),
                      label: '${carbG.round()} g',
                      onChanged: (v) => setLocal(() {
                        carbG = v;
                        calorieGoal = macroCals()
                            .clamp(_minCalories, _maxCalories)
                            .toDouble();
                      }),
                    ),
                    const SizedBox(height: 8),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Fats'),
                          Text('${fatG.round()} g'),
                        ]),
                    Slider(
                      value: fatG,
                      min: 20,
                      max: 250,
                      divisions: 230,
                      label: '${fatG.round()} g',
                      onChanged: (v) => setLocal(() {
                        fatG = v;
                        calorieGoal = macroCals()
                            .clamp(_minCalories, _maxCalories)
                            .toDouble();
                      }),
                    ),
                    Builder(builder: (_) {
                      final pfCals = proteinG * 4 + fatG * 9;
                      if (pfCals > calorieGoal + 1e-6) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Protein + fat alone exceed the Cal target by ${(pfCals - calorieGoal).round()} Cal.',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  setState(() {
                    _calorieGoal = calorieGoal.toDouble();
                    _proteinGoalG = proteinG.toDouble();
                    _carbGoalG = carbG.toDouble();
                    _fatGoalG = fatG.toDouble();
                  });

                  final ref = _docRef;
                  if (ref != null) {
                    await ref.set({
                      'calories_override': _calorieGoal,
                      'protein_g_override': _proteinGoalG,
                      'carb_g_override': _carbGoalG,
                      'fat_g_override': _fatGoalG,
                      'updated_at': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                  }

                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Macros saved')),
                  );
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        });
      },
    );
  }

  // ===================== HELPERS =====================

  void _recomputeFromGoals() {
    // 1) BMR: Mifflin–St Jeor
    final bmr = _sex == 'female'
        ? (10 * _weightKg + 6.25 * _heightCm - 5 * _age - 161)
        : (10 * _weightKg + 6.25 * _heightCm - 5 * _age + 5);

    // 2) Activity factor
    final activityFactor = switch (_activity) {
      'sedentary' => 1.2,
      'light' => 1.375,
      'moderate' => 1.55,
      'active' => 1.725,
      'veryactive' => 1.9,
      _ => 1.55,
    };

    // 3) TDEE
    final tdee = bmr * activityFactor;

    // 4) Weekly rate → daily Cal delta (7700 Cal per kg)
    final kcalDelta = (_rateKgPerWeek * 7700) / 7.0;

    // 5) Goal baseline
    double targetCal = tdee + kcalDelta;
    targetCal = targetCal.clamp(_minCalories, _maxCalories).toDouble();

    // 6) Macros:
    final proteinG = (_proteinGPerKg * _weightKg).clamp(50, 400).toDouble();
    final fatCal = (targetCal * (_fatPercent / 100.0));
    final fatG = (fatCal / 9.0).clamp(20, 250).toDouble();
    final remainingCal =
        (targetCal - (proteinG * 4 + fatG * 9)).clamp(0, 99999).toDouble();
    final carbG = (remainingCal / 4.0).clamp(0, _maxCarbG).toDouble();

    _calorieGoal = targetCal;
    _proteinGoalG = proteinG;
    _fatGoalG = fatG;
    _carbGoalG = carbG;
  }

  void _hydrateFromDoc(Map<String, dynamic> data) {
    _units = (data['units'] as String? ?? _units).toLowerCase();
    _sex = (data['sex'] as String? ?? _sex).toLowerCase();
    if (_sex != 'male' && _sex != 'female') _sex = 'male';
    _age = (data['age'] as num?)?.toInt() ?? _age;
    _heightCm = (data['height_cm'] as num?)?.toDouble() ?? _heightCm;
    _weightKg = (data['weight_kg'] as num?)?.toDouble() ?? _weightKg;
    _activity = (data['activity'] as String? ?? _activity).toLowerCase();
    _goal = (data['goal'] as String? ?? _goal).toLowerCase();
    _targetWeightKg =
        (data['target_weight_kg'] as num?)?.toDouble() ?? _targetWeightKg;
    _rateKgPerWeek =
        (data['rate_kg_per_week'] as num?)?.toDouble() ?? _rateKgPerWeek;
    _proteinGPerKg =
        (data['protein_g_per_kg'] as num?)?.toDouble() ?? _proteinGPerKg;
    _fatPercent = (data['fat_percent'] as num?)?.toDouble() ?? _fatPercent;
    _calorieGoal =
        (data['calories_override'] as num?)?.toDouble() ?? _calorieGoal;
    _proteinGoalG =
        (data['protein_g_override'] as num?)?.toDouble() ?? _proteinGoalG;
    _carbGoalG = (data['carb_g_override'] as num?)?.toDouble() ?? _carbGoalG;
    _fatGoalG = (data['fat_g_override'] as num?)?.toDouble() ?? _fatGoalG;
  }

  double _macroCalories() => _proteinGoalG * 4 + _carbGoalG * 4 + _fatGoalG * 9;

  String _rateLabel(double rateKgPerWeek, String units) {
    final arrow =
        rateKgPerWeek > 0 ? 'gain' : (rateKgPerWeek < 0 ? 'loss' : 'maintain');
    if (units == 'metric') {
      return '${rateKgPerWeek.toStringAsFixed(2)} kg/week • $arrow';
    } else {
      final lbsPerWeek = rateKgPerWeek * 2.2046226218;
      return '${lbsPerWeek.toStringAsFixed(2)} lb/week • $arrow';
    }
  }
}
