import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'db.dart';

void main() async {
  // Cross-platform database initialization
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else {
    // For desktop platforms (Windows, Linux, macOS), initialize FFI
    // For mobile platforms, the default sqflite factory will be used
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }
      // On mobile (Android/iOS), databaseFactory stays null
      // This is fine - default sqflite will be used
    } catch (e) {
      // Platform detection failed - fallback to default sqflite
      // The db.dart file will handle initialization if needed
    }
  }

  // Ensure admin user exists on app start
  try {
    final db = AppDatabase();
    final adminExists = await db.usernameExists('admin');
    if (!adminExists) {
      await db.createUser('admin', 'admin123');
    }
  } catch (e) {
    // If admin already exists or error occurs, continue
    // This ensures the app can still run
  }

  runApp(const BeautyBazaarApp());
}

class BeautyBazaarApp extends StatelessWidget {
  const BeautyBazaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(useMaterial3: true);
    const seed = Color(0xFFAD1457); // rich pink
    return MaterialApp(
      title: 'BeautyBazaar',
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: seed,
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BeautyBazaar 💅'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: const [
                  SizedBox(height: 8),
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: Colors.black,
                    backgroundImage: AssetImage('assets/images/logo.png'),
                  ),
                  SizedBox(height: 16),
                ],
              ),
            ),
            Text(
              'Welcome to BeautyBazaar!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Book your service and time, or login as admin to view revenue.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: const Text('Book an Appointment'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BookingScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('Admin Login'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  Service? _selectedService;
  DateTime? _selectedDateTime;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Initialize with first service - ensure it's never null
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ServicesCatalog.all.isNotEmpty && _selectedService == null) {
        setState(() {
          _selectedService = ServicesCatalog.all.first;
        });
      }
    });
    if (ServicesCatalog.all.isNotEmpty) {
      _selectedService = ServicesCatalog.all.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      initialDate: now,
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }
    
    // Double check that we have all required values
    final selectedService = _selectedService;
    final selectedDateTime = _selectedDateTime;
    
    if (selectedService == null || selectedDateTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select service, date and time')),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final booking = Booking(
        clientName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        serviceId: selectedService.id,
        serviceName: selectedService.name,
        priceKsh: selectedService.priceKsh,
        appointmentDateTime: selectedDateTime,
      );
      await AppDatabase().insertBooking(booking);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Booking Confirmed'),
          content: Text(
            'Thank you, your booking for ${selectedService.name} on ${DateFormat('EEE, d MMM yyyy • HH:mm').format(selectedDateTime)} is confirmed.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to home screen
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (_formKey.currentState != null) {
        _formKey.currentState!.reset();
      }
      setState(() {
        if (ServicesCatalog.all.isNotEmpty) {
          _selectedService = ServicesCatalog.all.first;
        }
        _selectedDateTime = null;
        _isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter a valid name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number'),
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().length < 9)
                    ? 'Enter a valid phone'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Service>(
                decoration: const InputDecoration(labelText: 'Service'),
                items: ServicesCatalog.all.isEmpty
                    ? null
                    : [
                        for (final s in ServicesCatalog.all)
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.name} — KSH ${s.priceKsh}'),
                          ),
                      ],
                value: _selectedService,
                onChanged: (s) {
                  if (s != null) {
                    setState(() => _selectedService = s);
                  }
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a service';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date & Time',
                    suffixIcon: Icon(Icons.schedule),
                  ),
                  child: Builder(
                    builder: (context) {
                      final dt = _selectedDateTime;
                      return Text(
                        dt == null
                            ? 'Select Date & Time'
                            : DateFormat(
                                'EEE, d MMM yyyy • HH:mm',
                              ).format(dt),
                        style: TextStyle(
                          color: dt == null 
                              ? Colors.grey[600] 
                              : Colors.black87,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirm Booking'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final db = AppDatabase();
      final isValid = await db.validateLogin(
        _userController.text.trim(),
        _passController.text.trim(),
      );

      if (!mounted) return;

      if (isValid) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Invalid credentials')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(labelText: 'Username'),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Enter username' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < 4) ? 'Enter password' : null,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _revenue = 0;
  List<Booking> _bookings = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = AppDatabase();
      final rev = await db.getMonthlyRevenueKsh(
        _selectedMonth.year,
        _selectedMonth.month,
      );
      final all = await db.getAllBookings();
      if (mounted) {
        setState(() {
          _revenue = rev;
          _bookings = all;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDate: _selectedMonth,
      helpText: 'Select any day in the month',
    );
    if (date == null) return;
    setState(() => _selectedMonth = DateTime(date.year, date.month));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSH ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Revenue — $monthLabel',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          currency.format(_revenue),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.date_range),
                  label: const Text('Change Month'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Bookings',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_bookings.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: Text('No bookings found')),
              )
            else
              for (final b in _bookings)
                Card(
                  child: ListTile(
                    title: Text('${b.clientName} — ${b.serviceName}'),
                    subtitle: Text(
                      '${DateFormat('EEE, d MMM • HH:mm').format(b.appointmentDateTime)}   •   KSH ${b.priceKsh}   •   ${b.status}',
                    ),
                    leading: Icon(
                      b.status == 'active' ? Icons.check_circle : Icons.cancel,
                      color: b.status == 'active' ? Colors.green : Colors.red,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
