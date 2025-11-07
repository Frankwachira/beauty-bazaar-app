import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'db.dart';
import 'utils.dart';

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

  runApp(const BeautyBazaarApp());
}

class BeautyBazaarApp extends StatefulWidget {
  const BeautyBazaarApp({super.key});

  @override
  State<BeautyBazaarApp> createState() => _BeautyBazaarAppState();
}

class _BeautyBazaarAppState extends State<BeautyBazaarApp> {
  bool _isInitialized = false;
  bool _hasUsers = false;

  @override
  void initState() {
    super.initState();
    _checkUsers();
  }

  Future<void> _checkUsers() async {
    try {
      AppLogger.debug('Checking if users exist in database');
      final db = AppDatabase();
      
      // Ensure database is initialized
      await db.database;
      
      final hasUsers = await db.hasAnyUsers();
      AppLogger.debug('Users exist: $hasUsers');
      
      if (mounted) {
        setState(() {
          _hasUsers = hasUsers;
          _isInitialized = true;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error checking users', e, stackTrace, 'BeautyBazaarApp');
      if (mounted) {
        setState(() {
          _hasUsers = false;
          _isInitialized = true;
        });
      }
    }
  }
  
  // Method to refresh user check (can be called after account creation)
  void refreshUserCheck() {
    _checkUsers();
  }

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
      home: _isInitialized
          ? (_hasUsers ? const HomeScreen() : const SetupScreen())
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isCreating = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAdmin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();
      
      if (username.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username cannot be empty')),
        );
        setState(() => _isCreating = false);
        return;
      }
      
      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password cannot be empty')),
        );
        setState(() => _isCreating = false);
        return;
      }
      
      AppLogger.info('Creating admin account: $username');
      final db = AppDatabase();
      
      // Ensure database is initialized
      await db.database;
      
      await db.createUser(username, password);
      AppLogger.info('Admin account created successfully');

      if (!mounted) return;

      // Verify the user was actually created
      final userExists = await db.usernameExists(username);
      if (!userExists) {
        throw Exception('User creation failed - user not found after creation');
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin account created successfully!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Wait a moment for database to be fully updated
      await Future.delayed(const Duration(milliseconds: 300));

      // Navigate to home screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error creating admin account', e, stackTrace, 'SetupScreen');
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating account: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Your Salon'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.store,
                size: 80,
                color: Color(0xFFAD1457),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to BeautyBazaar!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create your admin account to start managing your salon',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Admin Username',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => (v == null || v.trim().length < 3)
                    ? 'Username must be at least 3 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) => (v == null || v.length < 4)
                    ? 'Password must be at least 4 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please confirm your password'
                    : null,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isCreating ? null : _createAdmin,
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Admin Account'),
              ),
            ],
          ),
        ),
      ),
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
  DateTime? _selectedDate;
  DateTime? _selectedDateTime;
  bool _isSubmitting = false;
  bool _isLoadingSlots = false;
  Map<DateTime, bool> _timeSlotAvailability = {};

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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final db = AppDatabase();
    
    // Get fully booked dates for the current month and next few months
    final currentMonth = DateTime(now.year, now.month);
    final Set<DateTime> fullyBookedDates = {};
    
    // Check current month and next 3 months
    for (int i = 0; i < 4; i++) {
      final month = DateTime(currentMonth.year, currentMonth.month + i);
      final bookedDates = await db.getFullyBookedDates(month.year, month.month);
      fullyBookedDates.addAll(bookedDates);
    }
    
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      initialDate: _selectedDate ?? now,
      selectableDayPredicate: (DateTime day) {
        // Allow selection of all days, but we'll show indicators
        return true;
      },
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFFAD1457),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              // Mark fully booked dates
              onSurfaceVariant: Colors.grey,
            ),
          ),
          child: Builder(
            builder: (context) {
              // Customize the calendar to show fully booked dates
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.of(context).textScaler,
                ),
                child: child!,
              );
            },
          ),
        );
      },
    );
    if (date == null) return;
    
    // Check if the selected date is fully booked
    final isFullyBooked = fullyBookedDates.contains(
      DateTime(date.year, date.month, date.day),
    );
    
    if (isFullyBooked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This date is fully booked. Please select another date.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    setState(() {
      _selectedDate = date;
      _selectedDateTime = null; // Reset time selection when date changes
      _timeSlotAvailability = {};
    });
    
    // Load time slot availability for the selected date
    await _loadTimeSlots(date);
  }

  Future<void> _loadTimeSlots(DateTime date) async {
    if (_selectedService == null) return;
    
    setState(() => _isLoadingSlots = true);
    
    try {
      final db = AppDatabase();
      final availability = await db.getTimeSlotAvailability(
        date,
        _selectedService!.durationMinutes,
      );
      
      if (mounted) {
        setState(() {
          _timeSlotAvailability = availability;
          _isLoadingSlots = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error loading time slots', e, stackTrace, 'BookingScreen');
      if (mounted) {
        setState(() => _isLoadingSlots = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading time slots: ${e.toString()}')),
        );
      }
    }
  }

  void _selectTimeSlot(DateTime timeSlot) {
    if (_timeSlotAvailability[timeSlot] == true) {
      setState(() {
        _selectedDateTime = timeSlot;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This time slot is already booked')),
      );
    }
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}min';
    } else if (minutes == 60) {
      return '1hr';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) {
        return '${hours}hrs';
      } else {
        return '${hours}hr ${mins}min';
      }
    }
  }

  Widget _buildTimeSlotGrid() {
    if (_selectedDate == null || _selectedService == null) {
      return const SizedBox.shrink();
    }

    // Get only available slots and sort them
    final availableSlots = _timeSlotAvailability.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) => a.compareTo(b));
    
    // Also get booked slots for display
    final bookedSlots = _timeSlotAvailability.entries
        .where((entry) => entry.value == false)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) => a.compareTo(b));
    
    // Combine and sort all slots
    final allSlots = [...availableSlots, ...bookedSlots]
      ..sort((a, b) => a.compareTo(b));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: allSlots.map((slot) {
        final isAvailable = availableSlots.contains(slot);
        final isSelected = _selectedDateTime != null &&
            _selectedDateTime!.year == slot.year &&
            _selectedDateTime!.month == slot.month &&
            _selectedDateTime!.day == slot.day &&
            _selectedDateTime!.hour == slot.hour &&
            _selectedDateTime!.minute == slot.minute;

        return GestureDetector(
          onTap: isAvailable ? () => _selectTimeSlot(slot) : null,
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : isAvailable
                      ? Colors.green.shade50
                      : Colors.grey.shade300,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : isAvailable
                        ? Colors.green
                        : Colors.grey,
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(slot),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : isAvailable
                            ? Colors.green.shade900
                            : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  isAvailable ? Icons.check_circle : Icons.cancel,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : isAvailable
                          ? Colors.green
                          : Colors.grey,
                ),
                Text(
                  isAvailable ? 'Free' : 'Booked',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected
                        ? Colors.white
                        : isAvailable
                            ? Colors.green.shade900
                            : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFullyBookedIndicator() {
    return FutureBuilder<bool>(
      future: _selectedDate != null
          ? AppDatabase().isDateFullyBooked(_selectedDate!)
          : Future.value(false),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == true) {
          return Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.event_busy, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This date is fully booked',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildBookingInfoCard({
    required String service,
    required String date,
    required String startTime,
    required String endTime,
    required String duration,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            service,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(date),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.access_time, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text('$startTime - $endTime ($duration)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookedTimeBlocks() {
    if (_selectedDate == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: AppDatabase().getBookingsWithEndTimes(_selectedDate!),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final bookings = snapshot.data!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Booked Time Blocks',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ...bookings.map((bookingInfo) {
              final booking = bookingInfo['booking'] as Booking;
              final startTime = bookingInfo['startTime'] as DateTime;
              final endTime = bookingInfo['endTime'] as DateTime;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            booking.serviceName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState == null || !_formKey.currentState!.validate()) {
      return;
    }
    
    // Double check that we have all required values
    final selectedService = _selectedService;
    final selectedDateTime = _selectedDateTime;
    
    if (selectedService == null || _selectedDate == null || selectedDateTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select service, date and time')),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Normalize phone number before saving
      final normalizedPhone = PhoneValidator.normalizePhone(_phoneController.text.trim());
      if (normalizedPhone == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid phone number format')),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }

      // Check for booking conflicts before submitting
      final db = AppDatabase();
      final hasConflict = await db.hasBookingConflict(
        selectedDateTime,
        selectedService.durationMinutes,
      );
      
      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This time slot is no longer available. Please select another time.'),
            ),
          );
        }
        setState(() => _isSubmitting = false);
        // Reload time slots to reflect current availability
        if (_selectedDate != null) {
          await _loadTimeSlots(_selectedDate!);
        }
        return;
      }

      AppLogger.info('Creating booking for ${_nameController.text.trim()}');
      
      // Calculate end time based on service duration
      final endTime = selectedDateTime.add(Duration(minutes: selectedService.durationMinutes));
      
      final booking = Booking(
        clientName: _nameController.text.trim(),
        phoneNumber: normalizedPhone,
        serviceId: selectedService.id,
        serviceName: selectedService.name,
        priceKsh: selectedService.priceKsh,
        appointmentDateTime: selectedDateTime,
      );
      await AppDatabase().insertBooking(booking);
      AppLogger.info('Booking created successfully: ${booking.id}');
      
      // Reload time slots immediately to reflect the new booking
      if (_selectedDate != null) {
        await _loadTimeSlots(_selectedDate!);
      }
      
      if (!mounted) return;

      // Show confirmation dialog with start and end times
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Booking Confirmed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thank you! Your booking is confirmed.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              _buildBookingInfoCard(
                service: selectedService.name,
                date: DateFormat('EEE, d MMM yyyy').format(selectedDateTime),
                startTime: DateFormat('HH:mm').format(selectedDateTime),
                endTime: DateFormat('HH:mm').format(endTime),
                duration: _formatDuration(selectedService.durationMinutes),
              ),
            ],
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
        _selectedDate = null;
        _selectedDateTime = null;
        _timeSlotAvailability = {};
        _isSubmitting = false;
      });
    } catch (e, stackTrace) {
      AppLogger.error('Error creating booking', e, stackTrace, 'BookingScreen');
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
                validator: (v) => PhoneValidator.getValidationError(v),
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
                            child: Text('${s.name} — KSH ${s.priceKsh} (${_formatDuration(s.durationMinutes)})'),
                          ),
                      ],
                value: _selectedService,
                onChanged: (s) {
                  if (s != null) {
                    setState(() {
                      _selectedService = s;
                      _selectedDateTime = null;
                      _timeSlotAvailability = {};
                    });
                    // Reload time slots if date is already selected
                    if (_selectedDate != null) {
                      _loadTimeSlots(_selectedDate!);
                    }
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
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Builder(
                    builder: (context) {
                      final date = _selectedDate;
                      return Text(
                        date == null
                            ? 'Select Date'
                            : DateFormat('EEE, d MMM yyyy').format(date),
                        style: TextStyle(
                          color: date == null 
                              ? Colors.grey[600] 
                              : Colors.black87,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_selectedDate != null) ...[
                const SizedBox(height: 16),
                _buildFullyBookedIndicator(),
                _buildBookedTimeBlocks(),
                Text(
                  'Available Time Slots',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_selectedDateTime != null && _selectedService != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected Time Slot',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${DateFormat('HH:mm').format(_selectedDateTime!)} - ${DateFormat('HH:mm').format(_selectedDateTime!.add(Duration(minutes: _selectedService!.durationMinutes)))} (${_formatDuration(_selectedService!.durationMinutes)})',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_isLoadingSlots)
                  const Center(child: CircularProgressIndicator())
                else if (_timeSlotAvailability.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No available time slots for this date'),
                  )
                else
                  _buildTimeSlotGrid(),
              ],
              const SizedBox(height: 20),
              // Show button only when all required fields are filled
              if (_selectedService != null && _selectedDate != null && _selectedDateTime != null)
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Confirm Booking',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                )
              else
                ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text(
                    'Select Date and Time to Continue',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              const SizedBox(height: 20), // Extra space at bottom for scrolling
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

    final username = _userController.text.trim();
    final password = _passController.text.trim();
    
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your username')),
      );
      return;
    }
    
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      AppLogger.info('Admin login attempt for $username');
      final db = AppDatabase();
      
      // Ensure database is initialized
      await db.database;
      
      final isValid = await db.validateLogin(username, password);

      if (!mounted) return;

      if (isValid) {
        AppLogger.info('Admin login successful');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        }
      } else {
        AppLogger.warning('Admin login failed: invalid credentials');
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(
            content: Text('Invalid username or password. Please try again.'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error during admin login', e, stackTrace, 'AdminLoginScreen');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text('Login error: ${e.toString()}'),
        backgroundColor: Colors.red,
      ));
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

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  int _revenue = 0;
  List<Booking> _bookings = const [];
  List<Service> _services = const [];
  int _totalBookings = 0;
  Map<int, int> _peakHours = {};
  List<Map<String, dynamic>> _popularServices = [];
  int _totalRevenue = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      AppLogger.debug('Loading admin dashboard data');
      final db = AppDatabase();
      final rev = await db.getMonthlyRevenueKsh(
        _selectedMonth.year,
        _selectedMonth.month,
      );
      final all = await db.getAllBookings();
      final services = await db.getAllServices();
      final totalBookings = await db.getTotalBookings();
      final peakHours = await db.getPeakHours();
      final popularServices = await db.getMostPopularServices();
      final totalRevenue = await db.getTotalRevenue();
      
      AppLogger.debug('Loaded ${all.length} bookings, revenue: KSH $rev');
      if (mounted) {
        setState(() {
          _revenue = rev;
          _bookings = all;
          _services = services;
          _totalBookings = totalBookings;
          _peakHours = peakHours;
          _popularServices = popularServices;
          _totalRevenue = totalRevenue;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error loading admin dashboard data', e, stackTrace, 'AdminDashboard');
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

  Future<void> _cancelBooking(int bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, Cancel'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      AppLogger.info('Cancelling booking: $bookingId');
      final db = AppDatabase();
      await db.cancelBooking(bookingId);
      AppLogger.info('Booking cancelled successfully: $bookingId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking cancelled successfully')),
        );
        await _load(); // Refresh the list
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error cancelling booking', e, stackTrace, 'AdminDashboard');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling booking: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _editBooking(Booking booking) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditBookingScreen(booking: booking),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _deleteBooking(int bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Booking'),
        content: const Text('Are you sure you want to permanently delete this booking? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      AppLogger.info('Deleting booking: $bookingId');
      final db = AppDatabase();
      await db.deleteBooking(bookingId);
      AppLogger.info('Booking deleted successfully: $bookingId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking deleted successfully')),
        );
        await _load();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting booking', e, stackTrace, 'AdminDashboard');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting booking: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final currency = NumberFormat.currency(locale: 'en_KE', symbol: 'KSH ');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.book_online), text: 'Bookings'),
            Tab(icon: Icon(Icons.spa), text: 'Services'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
          ],
        ),
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
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildBookingsTab(monthLabel, currency),
            _buildServicesTab(),
            _buildAnalyticsTab(currency),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsTab(String monthLabel, NumberFormat currency) {
    return ListView(
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
          'All Bookings',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_bookings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('No bookings found')),
          )
        else
          for (final b in _bookings)
            Builder(
              builder: (context) {
                final service = ServicesCatalog.getById(b.serviceId);
                final startTime = b.appointmentDateTime;
                final endTime = service != null
                    ? startTime.add(Duration(minutes: service.durationMinutes))
                    : startTime;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${b.clientName} — ${b.serviceName}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${DateFormat('EEE, d MMM').format(startTime)}   •   ${DateFormat('HH:mm').format(startTime)} - ${DateFormat('HH:mm').format(endTime)}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Phone: ${b.phoneNumber}   •   KSH ${b.priceKsh}   •   ${b.status}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    leading: Icon(
                      b.status == 'active' ? Icons.check_circle : Icons.cancel,
                      color: b.status == 'active' ? Colors.green : Colors.red,
                    ),
                    trailing: b.id != null
                        ? PopupMenuButton(
                            itemBuilder: (context) => [
                              if (b.status == 'active')
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                              if (b.status == 'active')
                                const PopupMenuItem(
                                  value: 'cancel',
                                  child: Row(
                                    children: [
                                      Icon(Icons.cancel, color: Colors.orange, size: 20),
                                      SizedBox(width: 8),
                                      Text('Cancel'),
                                    ],
                                  ),
                                ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red, size: 20),
                                    SizedBox(width: 8),
                                    Text('Delete'),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'edit') {
                                _editBooking(b);
                              } else if (value == 'cancel') {
                                _cancelBooking(b.id!);
                              } else if (value == 'delete') {
                                _deleteBooking(b.id!);
                              }
                            },
                          )
                        : null,
                  ),
                );
              },
            ),
      ],
    );
  }

  Widget _buildServicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Services',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _addService(),
              icon: const Icon(Icons.add),
              label: const Text('Add Service'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_services.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('No services found')),
          )
        else
          for (final service in _services)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(service.name),
                subtitle: Text(
                  'KSH ${service.priceKsh}   •   ${_formatDuration(service.durationMinutes)}',
                ),
                trailing: PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editService(service);
                    } else if (value == 'delete') {
                      _deleteService(service.id);
                    }
                  },
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildAnalyticsTab(NumberFormat currency) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Total Bookings Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.book_online, size: 40, color: Colors.blue),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Bookings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '$_totalBookings',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Total Revenue Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.attach_money, size: 40, color: Colors.green),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Revenue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        currency.format(_totalRevenue),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Peak Hours
        Text(
          'Peak Hours',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_peakHours.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('No peak hours data available')),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: _peakHours.entries.map((entry) {
                  final hour = entry.key;
                  final count = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${hour.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 100,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: count / (_peakHours.values.reduce((a, b) => a > b ? a : b)),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$count bookings'),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        const SizedBox(height: 24),
        // Most Popular Services
        Text(
          'Most Popular Services',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_popularServices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: Text('No popular services data available')),
          )
        else
          for (final service in _popularServices)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(service['service_name'] as String),
                subtitle: Text(
                  '${service['booking_count']} bookings   •   ${currency.format(service['total_revenue'] as int)}',
                ),
                leading: const Icon(Icons.star, color: Colors.amber),
                trailing: Text(
                  '#${_popularServices.indexOf(service) + 1}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}min';
    } else if (minutes == 60) {
      return '1hr';
    } else {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) {
        return '${hours}hrs';
      } else {
        return '${hours}hr ${mins}min';
      }
    }
  }

  Future<void> _addService() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ServiceEditScreen()),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _editService(Service service) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ServiceEditScreen(service: service)),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _deleteService(String serviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service'),
        content: const Text('Are you sure you want to delete this service? This will remove it from the service list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      AppLogger.info('Deleting service: $serviceId');
      final db = AppDatabase();
      await db.deleteService(serviceId);
      AppLogger.info('Service deleted successfully: $serviceId');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service deleted successfully')),
        );
        await _load();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error deleting service', e, stackTrace, 'AdminDashboard');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting service: ${e.toString()}')),
        );
      }
    }
  }
}

// Edit Booking Screen
class EditBookingScreen extends StatefulWidget {
  final Booking booking;
  const EditBookingScreen({super.key, required this.booking});

  @override
  State<EditBookingScreen> createState() => _EditBookingScreenState();
}

class _EditBookingScreenState extends State<EditBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  Service? _selectedService;
  DateTime? _selectedDate;
  DateTime? _selectedTime;
  bool _isSubmitting = false;
  List<Service> _services = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.booking.clientName);
    _phoneController = TextEditingController(text: widget.booking.phoneNumber);
    _selectedDate = widget.booking.appointmentDateTime;
    _selectedTime = widget.booking.appointmentDateTime;
    _loadServices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    try {
      final db = AppDatabase();
      final services = await db.getAllServices();
      setState(() {
        _services = services;
        _selectedService = services.firstWhere(
          (s) => s.id == widget.booking.serviceId,
          orElse: () => services.first,
        );
      });
    } catch (e) {
      AppLogger.error('Error loading services', e, null, 'EditBookingScreen');
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime ?? DateTime.now()),
    );
    if (time != null && _selectedDate != null) {
      setState(() {
        _selectedTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedService == null || _selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = AppDatabase();
      final updatedBooking = widget.booking.copyWith(
        clientName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        serviceId: _selectedService!.id,
        serviceName: _selectedService!.name,
        priceKsh: _selectedService!.priceKsh,
        appointmentDateTime: _selectedTime!,
      );

      await db.updateBooking(updatedBooking);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking updated successfully')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error updating booking', e, stackTrace, 'EditBookingScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating booking: ${e.toString()}')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Booking')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Client Name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter client name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
              validator: PhoneValidator.getValidationError,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Service>(
              value: _selectedService,
              decoration: const InputDecoration(labelText: 'Service'),
              items: _services.map((service) {
                return DropdownMenuItem(
                  value: service,
                  child: Text('${service.name} - KSH ${service.priceKsh}'),
                );
              }).toList(),
              onChanged: (service) => setState(() => _selectedService = service),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(_selectedDate == null
                  ? 'Select Date'
                  : DateFormat('EEE, d MMM yyyy').format(_selectedDate!)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.access_time),
              label: Text(_selectedTime == null
                  ? 'Select Time'
                  : DateFormat('HH:mm').format(_selectedTime!)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update Booking'),
            ),
          ],
        ),
      ),
    );
  }
}

// Service Edit Screen
class ServiceEditScreen extends StatefulWidget {
  final Service? service;
  const ServiceEditScreen({super.key, this.service});

  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _durationController;
  late TextEditingController _idController;
  bool _isSubmitting = false;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.service != null;
    _nameController = TextEditingController(text: widget.service?.name ?? '');
    _priceController = TextEditingController(text: widget.service?.priceKsh.toString() ?? '');
    _durationController = TextEditingController(text: widget.service?.durationMinutes.toString() ?? '');
    _idController = TextEditingController(text: widget.service?.id ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _durationController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final db = AppDatabase();
      final service = Service(
        id: _idController.text.trim().toLowerCase().replaceAll(' ', '_'),
        name: _nameController.text.trim(),
        priceKsh: int.parse(_priceController.text.trim()),
        durationMinutes: int.parse(_durationController.text.trim()),
      );

      if (_isEditMode) {
        await db.updateService(service);
      } else {
        await db.addService(service);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditMode ? 'Service updated successfully' : 'Service added successfully')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error saving service', e, stackTrace, 'ServiceEditScreen');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving service: ${e.toString()}')),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? 'Edit Service' : 'Add Service')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isEditMode)
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: 'Service ID',
                  hintText: 'e.g., manicure_pedicure',
                  helperText: 'Lowercase, use underscores for spaces',
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter service ID' : null,
              )
            else
              TextFormField(
                controller: _idController,
                decoration: const InputDecoration(labelText: 'Service ID'),
                enabled: false,
              ),
            if (!_isEditMode) const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Service Name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter service name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Price (KSH)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter price';
                if (int.tryParse(v) == null) return 'Enter valid number';
                if (int.parse(v) <= 0) return 'Price must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
                helperText: 'e.g., 60 for 1 hour, 90 for 1.5 hours',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter duration';
                if (int.tryParse(v) == null) return 'Enter valid number';
                if (int.parse(v) <= 0) return 'Duration must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditMode ? 'Update Service' : 'Add Service'),
            ),
          ],
        ),
      ),
    );
  }
}
