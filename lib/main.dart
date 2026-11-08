import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const ParkEaseApp());
}

// ------------------------------------------------------------
// APP THEME
// ------------------------------------------------------------

class ParkEaseApp extends StatelessWidget {
  const ParkEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B1220);
    const panel = Color(0xFF111827);
    const blue = Color(0xFF3B82F6);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ParkEase',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: panel,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF263244)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: blue, width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const ParkEaseHome(),
    );
  }
}

// ------------------------------------------------------------
// MODELS
// ------------------------------------------------------------

class ParkingSlot {
  final String id;
  final bool isOccupied;

  ParkingSlot({required this.id, required this.isOccupied});
}

class BookingRecord {
  final String id;
  final String slotId;
  final DateTime bookingTime;
  final String status;
  final String customerName;
  final String vehicleNumber;
  final String phone;

  BookingRecord({
    required this.id,
    required this.slotId,
    required this.bookingTime,
    required this.status,
    this.customerName = 'Customer',
    this.vehicleNumber = '',
    this.phone = '',
  });
}

class BookingFormResult {
  final String customerName;
  final String vehicleNumber;
  final String phone;

  BookingFormResult({
    required this.customerName,
    required this.vehicleNumber,
    required this.phone,
  });
}

// ------------------------------------------------------------
// REUSABLE METRIC CARD
// ------------------------------------------------------------

class MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF263244)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 27),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              value,
              key: ValueKey(value),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------
// MAIN HOME SCREEN
// ------------------------------------------------------------

class ParkEaseHome extends StatefulWidget {
  const ParkEaseHome({super.key});

  @override
  State<ParkEaseHome> createState() => _ParkEaseHomeState();
}

class _ParkEaseHomeState extends State<ParkEaseHome> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  int selectedIndex = 0;
  String? selectedSlot;

  List<ParkingSlot> slots = [];
  List<BookingRecord> bookings = [];

  bool loading = true;
  String? loadError;

  StreamSubscription? slotSubscription;
  StreamSubscription? bookingSubscription;
  Timer? refreshTimer;

  static const Duration cancellationWindow = Duration(minutes: 5);

  static const Color panelColor = Color(0xFF111827);
  static const Color blueColor = Color(0xFF3B82F6);

  final List<String> pageTitles = [
    'Dashboard',
    'Parking Slots',
    'Bookings',
    'Payments',
    'Settings',
  ];

  final List<IconData> pageIcons = [
    Icons.dashboard_outlined,
    Icons.local_parking_outlined,
    Icons.book_online_outlined,
    Icons.receipt_long_outlined,
    Icons.settings_outlined,
  ];

  CollectionReference<Map<String, dynamic>> get slotCollection =>
      db.collection('parkingSlots');

  CollectionReference<Map<String, dynamic>> get bookingCollection =>
      db.collection('bookings');

  @override
  void initState() {
    super.initState();

    initializeFirestore();

    refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  // ----------------------------------------------------------
  // FIREBASE INITIALIZATION
  // ----------------------------------------------------------

  Future<void> initializeFirestore() async {
    try {
      final snapshot = await slotCollection.get();

      final existingIds = snapshot.docs.map((d) => d.id).toSet();

      final batch = db.batch();

      for (int i = 1; i <= 12; i++) {
        final id = 'A$i';

        if (!existingIds.contains(id)) {
          batch.set(slotCollection.doc(id), {
            'isOccupied': i == 2 || i == 5 || i == 9,
          });
        }
      }

      await batch.commit();

      slotSubscription = slotCollection.snapshots().listen(
        (snapshot) {
          if (!mounted) return;

          setState(() {
            slots =
                snapshot.docs.map((doc) {
                  return ParkingSlot(
                    id: doc.id,
                    isOccupied: doc.data()['isOccupied'] == true,
                  );
                }).toList()..sort(
                  (a, b) => int.parse(
                    a.id.substring(1),
                  ).compareTo(int.parse(b.id.substring(1))),
                );
          });
        },
        onError: (error) {
          if (mounted) {
            setState(() => loadError = error.toString());
          }
        },
      );

      bookingSubscription = bookingCollection
          .orderBy('bookingTime', descending: true)
          .snapshots()
          .listen(
            (snapshot) {
              if (!mounted) return;

              setState(() {
                bookings = snapshot.docs.map((doc) {
                  final data = doc.data();

                  return BookingRecord(
                    id: doc.id,
                    slotId: data['slotId'] ?? '',
                    bookingTime: (data['bookingTime'] as Timestamp).toDate(),
                    status: data['status'] ?? 'Active',
                    customerName: data['customerName'] ?? 'Customer',
                    vehicleNumber: data['vehicleNumber'] ?? '',
                    phone: data['phone'] ?? '',
                  );
                }).toList();

                loading = false;
              });
            },
            onError: (error) {
              if (mounted) {
                setState(() {
                  loading = false;
                  loadError = error.toString();
                });
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    slotSubscription?.cancel();
    bookingSubscription?.cancel();
    refreshTimer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------
  // GETTERS AND HELPERS
  // ----------------------------------------------------------

  int get availableSlots => slots.where((s) => !s.isOccupied).length;

  int get occupiedSlots => slots.where((s) => s.isOccupied).length;

  bool canCancelBooking(BookingRecord booking) {
    return booking.status == 'Active' &&
        DateTime.now().difference(booking.bookingTime) < cancellationWindow;
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void navigateTo(int index) {
    setState(() {
      selectedIndex = index;
      selectedSlot = null;
    });
  }

  String formatDate(DateTime date) {
    String d(int n) => n.toString().padLeft(2, '0');

    return '${d(date.day)}/${d(date.month)}/${date.year} '
        '${d(date.hour)}:${d(date.minute)}';
  }

  String remainingTime(BookingRecord booking) {
    final remaining =
        cancellationWindow - DateTime.now().difference(booking.bookingTime);

    if (remaining.inSeconds <= 0) {
      return 'Cancellation time expired';
    }

    return 'Time left to cancel: '
        '${remaining.inMinutes}m ${remaining.inSeconds % 60}s';
  }

  // ----------------------------------------------------------
  // SLOT SELECTION AND BOOKING
  // ----------------------------------------------------------

  void selectSlot(String id) {
    final slot = slots.firstWhere((s) => s.id == id);

    if (slot.isOccupied) {
      showMessage('This parking slot is already occupied.');
      return;
    }

    setState(() {
      selectedSlot = selectedSlot == id ? null : id;
    });
  }

  Future<void> openBookingForm() async {
    if (selectedSlot == null) {
      showMessage('Please select an available parking slot.');
      return;
    }

    final slotId = selectedSlot!;

    // Navigator opens a separate booking screen.
    final result = await Navigator.push<BookingFormResult>(
      context,
      MaterialPageRoute(builder: (context) => BookingFormPage(slotId: slotId)),
    );

    if (result == null || !mounted) return;

    await bookSlot(slotId, result);
  }

  Future<void> bookSlot(String slotId, BookingFormResult details) async {
    final slotRef = slotCollection.doc(slotId);

    final now = DateTime.now();

    final bookingId = 'BK${now.microsecondsSinceEpoch}';

    final bookingRef = bookingCollection.doc(bookingId);

    try {
      await db.runTransaction((transaction) async {
        final slotSnapshot = await transaction.get(slotRef);

        if (!slotSnapshot.exists) {
          throw Exception('Parking slot does not exist.');
        }

        if (slotSnapshot.data()?['isOccupied'] == true) {
          throw Exception('This slot is already occupied.');
        }

        transaction.update(slotRef, {'isOccupied': true});

        transaction.set(bookingRef, {
          'slotId': slotId,
          'bookingTime': Timestamp.fromDate(now),
          'status': 'Active',
          'customerName': details.customerName,
          'vehicleNumber': details.vehicleNumber,
          'phone': details.phone,
        });
      });

      if (!mounted) return;

      setState(() {
        selectedSlot = null;
      });

      showMessage(
        'Slot $slotId booked successfully! '
        'You have 5 minutes to cancel.',
      );
    } catch (e) {
      showMessage('Booking failed: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------
  // CANCELLATION
  // ----------------------------------------------------------

  Future<void> cancelBooking() async {
    if (selectedSlot == null) return;

    final active = bookings.where(
      (b) => b.slotId == selectedSlot && b.status == 'Active',
    );

    if (active.isEmpty) {
      showMessage('No active booking found for this slot.');
      return;
    }

    await cancelBookingRecord(active.first);
  }

  Future<void> cancelBookingRecord(BookingRecord booking) async {
    if (!canCancelBooking(booking)) {
      showMessage('The 5-minute cancellation period has expired.');
      return;
    }

    final bookingRef = bookingCollection.doc(booking.id);
    final slotRef = slotCollection.doc(booking.slotId);

    try {
      await db.runTransaction((transaction) async {
        final bookingSnapshot = await transaction.get(bookingRef);

        final slotSnapshot = await transaction.get(slotRef);

        if (!bookingSnapshot.exists || !slotSnapshot.exists) {
          throw Exception('Booking or slot not found.');
        }

        final data = bookingSnapshot.data()!;

        final time = (data['bookingTime'] as Timestamp).toDate();

        if (data['status'] != 'Active') {
          throw Exception('This booking is no longer active.');
        }

        if (DateTime.now().difference(time) >= cancellationWindow) {
          throw Exception('The cancellation period has expired.');
        }

        transaction.update(bookingRef, {'status': 'Cancelled'});

        transaction.update(slotRef, {'isOccupied': false});
      });

      if (!mounted) return;

      setState(() {
        if (selectedSlot == booking.slotId) {
          selectedSlot = null;
        }
      });

      showMessage('Booking ${booking.id} cancelled successfully!');
    } catch (e) {
      showMessage('Cancellation failed: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------
  // RESPONSIVE SIDEBAR
  // ----------------------------------------------------------

  Widget buildSidebar() {
    return Material(
      color: panelColor,
      child: SizedBox(
        width: 225,
        child: Column(
          children: [
            const SizedBox(height: 25),
            const ListTile(
              leading: Icon(
                Icons.local_parking,
                color: Colors.blueAccent,
                size: 32,
              ),
              title: Text(
                'ParkEase',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 25),
            for (int i = 0; i < pageTitles.length; i++) sidebarItem(i),
            const Spacer(),
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.person)),
              title: Text('User'),
              subtitle: Text('Parking Member'),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget sidebarItem(int index) {
    final selected = selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: ListTile(
        selected: selected,
        selectedTileColor: const Color(0xFF1D4ED8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: Icon(pageIcons[index]),
        title: Text(pageTitles[index]),
        onTap: () => navigateTo(index),
      ),
    );
  }

  // ----------------------------------------------------------
  // METRIC CARDS
  // ----------------------------------------------------------

  Widget buildMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 850
            ? 3
            : width >= 450
            ? 2
            : 1;

        final cardWidth = (width - (columns - 1) * 12) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: const MetricCard(
                title: 'Total Slots',
                value: '12',
                icon: Icons.grid_view,
                color: Colors.blueAccent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Available',
                value: '$availableSlots',
                icon: Icons.check_circle,
                color: Colors.greenAccent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                title: 'Occupied',
                value: '$occupiedSlots',
                icon: Icons.directions_car,
                color: Colors.redAccent,
              ),
            ),
          ],
        );
      },
    );
  }

  // ----------------------------------------------------------
  // ANIMATED PARKING SLOT WIDGET
  // ----------------------------------------------------------

  Widget parkingSlot(ParkingSlot slot) {
    final selected = selectedSlot == slot.id;

    final color = selected
        ? Colors.blue.withValues(alpha: 0.25)
        : slot.isOccupied
        ? Colors.redAccent.withValues(alpha: 0.15)
        : Colors.green.withValues(alpha: 0.13);

    final borderColor = selected
        ? Colors.blueAccent
        : slot.isOccupied
        ? Colors.redAccent
        : Colors.green;

    return InkWell(
      onTap: () => selectSlot(slot.id),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Icon(
                Icons.directions_car,
                key: ValueKey(slot.isOccupied),
                color: slot.isOccupied ? Colors.redAccent : Colors.greenAccent,
                size: 28,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              slot.id,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 3),
            Text(
              slot.isOccupied
                  ? 'Occupied'
                  : selected
                  ? 'Selected'
                  : 'Available',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // PARKING GRID
  // ----------------------------------------------------------

  Widget parkingGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 850
            ? 4
            : width >= 500
            ? 3
            : 2;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slots.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            return parkingSlot(slots[index]);
          },
        );
      },
    );
  }

  // ----------------------------------------------------------
  // DASHBOARD SCREEN
  // ----------------------------------------------------------

  Widget dashboardPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildMetrics(),
          const SizedBox(height: 28),
          const Text(
            'Parking Overview',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF263244)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$availableSlots spaces available',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 18),
                parkingGrid(),
                const SizedBox(height: 18),
                const Wrap(
                  spacing: 15,
                  runSpacing: 8,
                  children: [
                    Text('🟢 Available'),
                    Text('🔴 Occupied'),
                    Text('🔵 Selected'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Quick Booking',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: Text(
                    'Selected Slot: ${selectedSlot ?? "None"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: selectedSlot == null ? null : openBookingForm,
                  icon: const Icon(Icons.book_online),
                  label: const Text('Book Slot'),
                ),
                OutlinedButton.icon(
                  onPressed: selectedSlot == null ? null : cancelBooking,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => navigateTo(1),
                  child: const Text('View All Slots'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // PARKING SLOTS SCREEN
  // ----------------------------------------------------------

  Widget parkingSlotsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Your Parking Slot',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap an available slot to select it.',
            style: TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 20),
          buildMetrics(),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                parkingGrid(),
                const SizedBox(height: 20),
                if (selectedSlot != null) ...[
                  Text(
                    '$selectedSlot selected',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: openBookingForm,
                      icon: const Icon(Icons.book_online),
                      label: const Text('Continue to Booking'),
                    ),
                  ),
                ] else
                  const Text(
                    'Select an available parking slot to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // BOOKING HISTORY SCREEN
  // ----------------------------------------------------------

  Widget bookingsPage() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking History',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${bookings.length} total booking records',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: bookings.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy, size: 55, color: Colors.white38),
                        SizedBox(height: 12),
                        Text('No bookings yet'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings[index];

                      final active = booking.status == 'Active';

                      final canCancel = canCancelBooking(booking);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Padding(
                          padding: const EdgeInsets.all(17),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      booking.id,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(booking.status),
                                    backgroundColor: active
                                        ? Colors.green.withValues(alpha: 0.2)
                                        : Colors.red.withValues(alpha: 0.2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text('Customer: ${booking.customerName}'),
                              const SizedBox(height: 6),
                              Text('Parking Slot: ${booking.slotId}'),
                              if (booking.vehicleNumber.isNotEmpty)
                                Text('Vehicle: ${booking.vehicleNumber}'),
                              const SizedBox(height: 6),
                              Text(formatDate(booking.bookingTime)),
                              if (active) ...[
                                const SizedBox(height: 8),
                                Text(
                                  remainingTime(booking),
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ],
                              if (canCancel) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: () => cancelBookingRecord(booking),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('Cancel Booking'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // PLACEHOLDER SCREENS
  // ----------------------------------------------------------

  Widget placeholderPage(String title, IconData icon, String description) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 60, color: Colors.blueAccent),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // CURRENT PAGE WITH ANIMATED TRANSITION
  // ----------------------------------------------------------

  Widget currentPage() {
    Widget page;

    switch (selectedIndex) {
      case 0:
        page = dashboardPage();
        break;
      case 1:
        page = parkingSlotsPage();
        break;
      case 2:
        page = bookingsPage();
        break;
      case 3:
        page = placeholderPage(
          'Payments',
          Icons.receipt_long,
          'Payment functionality is not implemented yet.',
        );
        break;
      case 4:
        page = placeholderPage(
          'Settings',
          Icons.settings,
          'Settings functionality is not implemented yet.',
        );
        break;
      default:
        page = dashboardPage();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(selectedIndex), child: page),
    );
  }

  // ----------------------------------------------------------
  // MAIN RESPONSIVE BUILD
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Firebase error:\n$loadError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final isMobile = width < 700;
        final isTablet = width >= 700 && width < 1100;

        return Scaffold(
          appBar: isMobile
              ? AppBar(
                  title: const Text(
                    'ParkEase',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(
                        Icons.local_parking,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                )
              : null,
          body: Row(
            children: [
              if (!isMobile && !isTablet) buildSidebar(),

              if (isTablet)
                NavigationRail(
                  backgroundColor: panelColor,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: navigateTo,
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    pageTitles.length,
                    (index) => NavigationRailDestination(
                      icon: Icon(pageIcons[index]),
                      label: Text(pageTitles[index]),
                    ),
                  ),
                ),

              Expanded(
                child: Column(
                  children: [
                    if (!isMobile)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        color: const Color(0xFF0F172A),
                        child: Text(
                          pageTitles[selectedIndex],
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(child: currentPage()),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: navigateTo,
                  backgroundColor: panelColor,
                  indicatorColor: blueColor.withValues(alpha: 0.25),
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  destinations: List.generate(
                    pageTitles.length,
                    (index) => NavigationDestination(
                      icon: Icon(pageIcons[index]),
                      label: pageTitles[index],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }
}

// ------------------------------------------------------------
// SEPARATE BOOKING FORM SCREEN
// ------------------------------------------------------------

class BookingFormPage extends StatefulWidget {
  final String slotId;

  const BookingFormPage({super.key, required this.slotId});

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final vehicleController = TextEditingController();
  final phoneController = TextEditingController();

  bool submitting = false;

  @override
  void dispose() {
    nameController.dispose();
    vehicleController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  void submitBooking() {
    if (!formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      submitting = true;
    });

    final result = BookingFormResult(
      customerName: nameController.text.trim(),
      vehicleNumber: vehicleController.text.trim().toUpperCase(),
      phone: phoneController.text.trim(),
    );

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Booking')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_parking,
                        size: 48,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Booking Details',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You selected parking slot ${widget.slotId}. '
                        'Enter your details to continue.',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      const SizedBox(height: 25),

                      // CUSTOMER NAME
                      const Text(
                        'Customer Name',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Enter your full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name.';
                          }

                          if (value.trim().length < 3) {
                            return 'Name must contain at least 3 characters.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // VEHICLE NUMBER
                      const Text(
                        'Vehicle Registration Number',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: vehicleController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          hintText: 'Example: TS09AB1234',
                          prefixIcon: Icon(Icons.directions_car_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your vehicle number.';
                          }

                          if (!RegExp(
                            r'^[A-Za-z0-9 -]{5,15}$',
                          ).hasMatch(value.trim())) {
                            return 'Enter a valid registration number.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // PHONE NUMBER
                      const Text(
                        'Phone Number',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: const InputDecoration(
                          hintText: 'Enter 10-digit phone number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          counterText: '',
                        ),
                        validator: (value) {
                          if (value == null ||
                              !RegExp(
                                r'^[6-9][0-9]{9}$',
                              ).hasMatch(value.trim())) {
                            return 'Enter a valid 10-digit phone number.';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blueAccent),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can cancel this booking '
                                'within 5 minutes.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // SUBMIT BUTTON
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: submitting ? null : submitBooking,
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Confirm Booking'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Go Back'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
