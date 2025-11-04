import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'db.dart';

void main() {
  // Cross-platform database initialization
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
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
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFFFF7FB),
        appBarTheme: const AppBarTheme(backgroundColor: seed, foregroundColor: Colors.white),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: seed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Text(
              'WHERE BEAUTY MEETS EXPERTS, Book your appoinment.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: const Text('Book an Appointment'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookingScreen()));
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Find/Cancel My Booking'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FindBookingScreen()));
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.lock),
              label: const Text('Admin Login'),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
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
  Service? _selectedService = ServicesCatalog.all.first;
  DateTime? _selectedDateTime;

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
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    final selectedService = _selectedService;
    final selectedDateTime = _selectedDateTime;
    if (selectedService == null || selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select service, date and time')));
      return;
    }
    final booking = Booking(
      clientName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      serviceId: selectedService.id,
      serviceName: selectedService.name,
      priceKsh: selectedService.priceKsh,
      appointmentDateTime: selectedDateTime,
    );
    try {
      await AppDatabase().insertBooking(booking);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving booking: $e')));
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Booking Confirmed'),
        content: Text('Thank you, your booking for ${selectedService.name} on ${DateFormat('EEE, d MMM yyyy • HH:mm').format(selectedDateTime)} is confirmed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
        ],
      ),
    );
    formState.reset();
    setState(() {
      _selectedService = ServicesCatalog.all.first;
      _selectedDateTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a valid name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 9) ? 'Enter a valid phone' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Service>(
              value: _selectedService,
              decoration: const InputDecoration(labelText: 'Service'),
              items: [
                for (final s in ServicesCatalog.all)
                  DropdownMenuItem(value: s, child: Text('${s.name} — KSH ${s.priceKsh}')),
              ],
              onChanged: (s) => setState(() => _selectedService = s),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_selectedDateTime == null ? 'Select Date & Time' : DateFormat('EEE, d MMM yyyy • HH:mm').format(_selectedDateTime!)),
              trailing: const Icon(Icons.schedule),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _submit, child: const Text('Confirm Booking')),
          ]),
        ),
      ),
    );
  }
}

class FindBookingScreen extends StatefulWidget {
  const FindBookingScreen({super.key});
  @override
  State<FindBookingScreen> createState() => _FindBookingScreenState();
}

class _FindBookingScreenState extends State<FindBookingScreen> {
  final _phoneController = TextEditingController();
  List<Booking> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final items = await AppDatabase().findBookingsByPhone(_phoneController.text.trim());
    setState(() {
      _results = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find/Cancel My Booking')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _search, child: const Text('Search')),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (!_loading)
              Expanded(
                child: ListView(
                  children: [
                    for (final b in _results)
                      Card(
                        child: ListTile(
                          title: Text('${b.serviceName} — KSH ${b.priceKsh}'),
                          subtitle: Text('${b.clientName} • ${DateFormat('EEE, d MMM • HH:mm').format(b.appointmentDateTime)}${b.status == 'cancelled' ? '   •   CANCELLED' : ''}'),
                          trailing: b.status == 'active'
                              ? IconButton(
                                  icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                  onPressed: () async {
                                    if (b.id == null) return;
                                    await AppDatabase().cancelBooking(b.id!);
                                    await _search();
                                  },
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminLimitedScreen extends StatelessWidget {
  const AdminLimitedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('You are logged in but do not have permission to view bookings or revenue. Please contact the owner.'),
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

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _login() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final username = _userController.text.trim();
    final password = _passController.text;
    final db = AppDatabase();
    db.validateLogin(username, password).then((ok) async {
      if (ok) {
        final role = await db.getUserRole(username);
        if (!mounted) return;
        if (role == 'owner') {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminDashboard()));
        } else {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminLimitedScreen()));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid credentials')));
      }
    }).catchError((e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login error: $e')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter username' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 4) ? 'Enter password' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _login, child: const Text('Login')),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminRegisterScreen()));
              },
              child: const Text('Create an admin account'),
            ),
          ]),
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
    final db = AppDatabase();
    final rev = await db.getMonthlyRevenueKsh(_selectedMonth.year, _selectedMonth.month);
    final all = await db.getAllBookings();
    setState(() {
      _revenue = rev;
      _bookings = all;
    });
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
      appBar: AppBar(title: const Text('Admin Dashboard')),
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
                        Text('Revenue — $monthLabel', style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(currency.format(_revenue), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(onPressed: _pickMonth, icon: const Icon(Icons.date_range), label: const Text('Change Month')),
              ],
            ),
            const SizedBox(height: 24),
            Text('Bookings', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final b in _bookings)
              Card(
                child: ListTile(
                  title: Text('${b.clientName} — ${b.serviceName}'),
                subtitle: Text('${DateFormat('EEE, d MMM • HH:mm').format(b.appointmentDateTime)}   •   KSH ${b.priceKsh}${b.status == 'cancelled' ? '   •   CANCELLED' : ''}'),
                  leading: const Icon(Icons.person),
                trailing: b.status == 'active'
                    ? IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                        tooltip: 'Cancel booking',
                        onPressed: () async {
                          await AppDatabase().cancelBooking(b.id!);
                          await _load();
                        },
                      )
                    : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminRegisterScreen extends StatefulWidget {
  const AdminRegisterScreen({super.key});
  @override
  State<AdminRegisterScreen> createState() => _AdminRegisterScreenState();
}

class _AdminRegisterScreenState extends State<AdminRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final username = _userController.text.trim();
    final password = _passController.text;
    try {
      await AppDatabase().createUser(username, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created. You can now login.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Admin Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Minimum 3 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) => (v == null || v.length < 6) ? 'Minimum 6 characters' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              validator: (v) => (v != _passController.text) ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _register, child: const Text('Create Account')),
          ]),
        ),
      ),
    );
  }
}
