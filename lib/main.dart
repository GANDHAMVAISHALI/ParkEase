
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ParkEaseApp());
}

class ParkEaseApp extends StatelessWidget {
  const ParkEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ParkEase',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
      ),
      home: const ParkEaseHome(),
    );
  }
}

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

  BookingRecord({
    required this.id,
    required this.slotId,
    required this.bookingTime,
    required this.status,
  });
}

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

  CollectionReference<Map<String, dynamic>> get slotCollection =>
      db.collection('parkingSlots');

  CollectionReference<Map<String, dynamic>> get bookingCollection =>
      db.collection('bookings');

  @override
  void initState() {
    super.initState();
    initializeFirestore();

    refreshTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

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

      slotSubscription = slotCollection.snapshots().listen((snapshot) {
        if (!mounted) return;

        setState(() {
          slots = snapshot.docs.map((doc) {
            return ParkingSlot(
              id: doc.id,
              isOccupied: doc.data()['isOccupied'] == true,
            );
          }).toList()
            ..sort((a, b) => int.parse(a.id.substring(1))
                .compareTo(int.parse(b.id.substring(1))));
        });
      }, onError: (error) {
        if (mounted) {
          setState(() => loadError = error.toString());
        }
      });

      bookingSubscription =
          bookingCollection.orderBy('bookingTime', descending: true)
              .snapshots().listen((snapshot) {
        if (!mounted) return;

        setState(() {
          bookings = snapshot.docs.map((doc) {
            final data = doc.data();
            return BookingRecord(
              id: doc.id,
              slotId: data['slotId'] ?? '',
              bookingTime: (data['bookingTime'] as Timestamp).toDate(),
              status: data['status'] ?? 'Active',
            );
          }).toList();

          loading = false;
        });
      }, onError: (error) {
        if (mounted) {
          setState(() {
            loading = false;
            loadError = error.toString();
          });
        }
      });
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

  int get availableSlots =>
      slots.where((s) => !s.isOccupied).length;

  int get occupiedSlots =>
      slots.where((s) => s.isOccupied).length;

  bool canCancelBooking(BookingRecord booking) {
    return booking.status == 'Active' &&
        DateTime.now().difference(booking.bookingTime) <
            cancellationWindow;
  }

  void selectSlot(String id) {
    final slot = slots.firstWhere((s) => s.id == id);
    if (slot.isOccupied) return;

    setState(() => selectedSlot = id);
  }

  Future<void> bookSlot() async {
    if (selectedSlot == null) {
      showMessage('Please select an available parking slot.');
      return;
    }

    final slotId = selectedSlot!;
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
        });
      });

      if (mounted) {
        setState(() => selectedSlot = null);
        showMessage(
          'Slot $slotId booked successfully! You have 5 minutes to cancel.',
        );
      }
    } catch (e) {
      showMessage('Booking failed: ${e.toString()}');
    }
  }

  Future<void> cancelBooking() async {
    if (selectedSlot == null) return;

    final active = bookings.where((b) =>
        b.slotId == selectedSlot && b.status == 'Active');

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

      if (mounted) {
        setState(() {
          if (selectedSlot == booking.slotId) selectedSlot = null;
        });
        showMessage('Booking ${booking.id} cancelled successfully!');
      }
    } catch (e) {
      showMessage('Cancellation failed: ${e.toString()}');
    }
  }

  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String formatDate(DateTime date) {
    String d(int n) => n.toString().padLeft(2, '0');
    return '${d(date.day)}/${d(date.month)}/${date.year}  '
        '${d(date.hour)}:${d(date.minute)}';
  }

  String remainingTime(BookingRecord booking) {
    final remaining = cancellationWindow -
        DateTime.now().difference(booking.bookingTime);

    if (remaining.inSeconds <= 0) return 'Cancellation time expired';

    return 'Time left to cancel: ${remaining.inMinutes}m '
        '${remaining.inSeconds % 60}s';
  }

  Widget buildSidebar() {
    return Material(
      color: const Color(0xFF111827),
      child: SizedBox(
        width: 220,
        child: Column(
          children: [
            const SizedBox(height: 30),
            const ListTile(
              leading: Icon(Icons.local_parking, color: Colors.blueAccent),
              title: Text(
                'ParkEase',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 30),
            sidebarItem(Icons.dashboard_outlined, 'Dashboard', 0),
            sidebarItem(Icons.local_parking_outlined, 'Parking Slots', 1),
            sidebarItem(Icons.book_online_outlined, 'Bookings', 2),
            sidebarItem(Icons.receipt_long_outlined, 'Payments', 3),
            sidebarItem(Icons.settings_outlined, 'Settings', 4),
            const Spacer(),
            const ListTile(
              leading: CircleAvatar(child: Icon(Icons.person)),
              title: Text('User'),
              subtitle: Text('Parking Member'),
            ),
          ],
        ),
      ),
    );
  }

  Widget sidebarItem(IconData icon, String title, int index) {
    final selected = selectedIndex == index;

    return ListTile(
      selected: selected,
      selectedTileColor: const Color(0xFF1D4ED8),
      leading: Icon(icon),
      title: Text(title),
      onTap: () => setState(() => selectedIndex = index),
    );
  }

  Widget metricCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF263244)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.blueAccent, size: 28),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(color: Colors.white54)),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget parkingSlot(ParkingSlot slot) {
    final selected = selectedSlot == slot.id;

    final color = selected
        ? Colors.blue
        : slot.isOccupied
            ? Colors.redAccent.withValues(alpha: 0.2)
            : Colors.green.withValues(alpha: 0.15);

    return InkWell(
      onTap: () => selectSlot(slot.id),
      child: Container(
        width: 82,
        height: 72,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.blueAccent
                : slot.isOccupied
                    ? Colors.redAccent
                    : Colors.green,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_car,
              color: slot.isOccupied ? Colors.redAccent : Colors.green,
            ),
            Text(slot.id, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              slot.isOccupied
                  ? 'Occupied'
                  : selected
                      ? 'Selected'
                      : 'Available',
              style: const TextStyle(fontSize: 9, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget dashboardPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            metricCard('Total Slots', '${slots.length}', Icons.grid_view),
            const SizedBox(width: 12),
            metricCard('Available', '$availableSlots', Icons.check_circle),
            const SizedBox(width: 12),
            metricCard('Occupied', '$occupiedSlots', Icons.directions_car),
          ]),
          const SizedBox(height: 30),
          const Text(
            'Parking Overview',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF263244)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$availableSlots spaces available',
                  style: const TextStyle(color: Colors.greenAccent),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: slots.map(parkingSlot).toList(),
                ),
                const SizedBox(height: 25),
                const Text('🟢 Available     🔴 Occupied     🔵 Selected'),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Quick Booking',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Selected Slot: ${selectedSlot ?? "None"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedSlot == null ? null : bookSlot,
                  child: const Text('Book Slot'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: selectedSlot == null ? null : cancelBooking,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget bookingsPage() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking History',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: bookings.isEmpty
                ? const Center(child: Text('No bookings yet'))
                : ListView.builder(
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      final booking = bookings[index];
                      final active = booking.status == 'Active';
                      final canCancel = canCancelBooking(booking);

                      return Card(
                        color: const Color(0xFF111827),
                        margin: const EdgeInsets.only(bottom: 14),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(
                                  booking.id,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  booking.status,
                                  style: TextStyle(
                                    color: active
                                        ? Colors.greenAccent
                                        : Colors.redAccent,
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Text('Parking Slot: ${booking.slotId}'),
                              const SizedBox(height: 8),
                              Text(formatDate(booking.bookingTime)),
                              if (active) ...[
                                const SizedBox(height: 8),
                                Text(remainingTime(booking)),
                              ],
                              if (canCancel) ...[
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: () =>
                                      cancelBookingRecord(booking),
                                  child: const Text('Cancel Booking'),
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

  Widget placeholderPage(
    String title,
    IconData icon,
    String description,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 55, color: Colors.blueAccent),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(description),
        ],
      ),
    );
  }

  Widget currentPage() {
    switch (selectedIndex) {
      case 0:
      case 1:
        return dashboardPage();
      case 2:
        return bookingsPage();
      case 3:
        return placeholderPage(
          'Payments',
          Icons.receipt_long,
          'Payment information will appear here.',
        );
      case 4:
        return placeholderPage(
          'Settings',
          Icons.settings,
          'Manage your preferences here.',
        );
      default:
        return dashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Firebase error:\n$loadError'),
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          buildSidebar(),
          Expanded(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  color: const Color(0xFF0F172A),
                  child: const Text(
                    'Welcome to ParkEase',
                    style: TextStyle(
                      fontSize: 22,
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
    );
  }
}
