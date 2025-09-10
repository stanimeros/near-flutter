import 'package:flutter/material.dart';
import 'package:flutter_near/services/detour_ratio_test.dart';

class DetourTestPage extends StatefulWidget {
  const DetourTestPage({super.key});

  @override
  State<DetourTestPage> createState() => _DetourTestPageState();
}

class _DetourTestPageState extends State<DetourTestPage> {
  String _selectedCity = 'ΘΕΣΣΑΛΟΝΙΚΗΣ';
  int _selectedK = 5;
  int _selectedUserA = 0;
  int _selectedUserB = 1;
  bool _isRunning = false;

  final List<String> _cities = ['ΘΕΣΣΑΛΟΝΙΚΗΣ', 'ΚΟΜΟΤΗΝΗΣ'];
  final List<int> _kValues = [5, 25, 100];
  final List<int> _userPoints = [0, 1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Detour Ratio Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure Test Parameters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              
              // City Selection
              Text('City:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              DropdownButton<String>(
                value: _selectedCity,
                isExpanded: true,
                items: _cities.map((String city) {
                  return DropdownMenuItem<String>(
                    value: city,
                    child: Text(city),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCity = newValue!;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // K Value Selection
              Text('K Value:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              DropdownButton<int>(
                value: _selectedK,
                isExpanded: true,
                items: _kValues.map((int k) {
                  return DropdownMenuItem<int>(
                    value: k,
                    child: Text('k = $k'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedK = newValue!;
                  });
                },
              ),
              SizedBox(height: 16),
              
              // User A Selection
              Text('User A Point:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              DropdownButton<int>(
                value: _selectedUserA,
                isExpanded: true,
                items: _userPoints.map((int point) {
                  return DropdownMenuItem<int>(
                    value: point,
                    child: Text('Point ${point + 1}'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedUserA = newValue!;
                    // Ensure User B is different from User A
                    if (_selectedUserB == _selectedUserA) {
                      _selectedUserB = (_selectedUserA + 1) % 5;
                    }
                  });
                },
              ),
              SizedBox(height: 16),
              
              // User B Selection
              Text('User B Point:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              DropdownButton<int>(
                value: _selectedUserB,
                isExpanded: true,
                items: _userPoints.where((int point) => point != _selectedUserA).map((int point) {
                  return DropdownMenuItem<int>(
                    value: point,
                    child: Text('Point ${point + 1}'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedUserB = newValue!;
                  });
                },
              ),
              SizedBox(height: 32),
              
              // Run Test Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isRunning ? null : _runTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: _isRunning 
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Running Test...'),
                        ],
                      )
                    : Text('Run Detour Ratio Test'),
                ),
              ),
              SizedBox(height: 16),
              
              // Run Full Test Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isRunning ? null : _runFullTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Run Full Test Suite'),
                ),
              ),
              SizedBox(height: 20),
              
              // Test Information
              Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Information',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Text('• Single test runs one combination and shows visualization'),
                      Text('• Full test runs all combinations (20 per city × 3 k values × 2 cities = 120 tests)'),
                      Text('• Results are exported as JSON file'),
                      Text('• Visualization shows SPOIs, clusters, and meeting points'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runTest() async {
    setState(() {
      _isRunning = true;
    });

    try {
      final city = _selectedCity == 'ΘΕΣΣΑΛΟΝΙΚΗΣ' ? DetourRatioTest.thessaloniki : DetourRatioTest.komotini;
      
      await DetourRatioTest.runSingleTestWithVisualization(
        context,
        city,
        _selectedK,
        _selectedUserA,
        _selectedUserB,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  Future<void> _runFullTest() async {
    setState(() {
      _isRunning = true;
    });

    try {
      final detourTest = DetourRatioTest();
      await detourTest.runDetourRatioTest();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Full test completed! Check console for results.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Full test failed: $e')),
        );
      }
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }
}
