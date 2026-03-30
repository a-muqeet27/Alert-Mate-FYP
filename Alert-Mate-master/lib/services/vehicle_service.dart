import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/vehicle.dart';
import 'firebase_auth_service.dart';


class VehicleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuthService _authService = FirebaseAuthService();

  /// Check if driver already has an assigned vehicle (enforce 1 vehicle per driver)
  Future<bool> _driverHasVehicle(String driverId) async {
    final snapshot = await _firestore
        .collection('vehicles')
        .where('assignedDriverId', isEqualTo: driverId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Add vehicle with smart driver assignment logic
  /// Returns: Vehicle if successful, null if owner needs driver registration
  Future<Vehicle?> addVehicleWithDriverCheck({
    required String make,
    required String model,
    required String year,
    required String licensePlate,
    required String ownerId,
    required String ownerEmail,
    required bool willOwnerDrive,
    required String type,
  }) async {
    try {
      print('🚗 Adding vehicle: $make $model');
      
      // Create vehicle document
      DocumentReference vehicleRef = await _firestore.collection('vehicles').add({
        'make': make,
        'model': model,
        'year': year,
        'licensePlate': licensePlate,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'Offline',
        'alertness': 0,
        'location': 'Unknown',
        'assignedDriverId': null,
        'pendingAssignment': !willOwnerDrive, // Mark for auto-assignment only if owner won't drive
        'pendingOwnerAssignment': willOwnerDrive, // NEW: Flag if waiting for OWNER to become driver
      });

      print('✅ Vehicle created: ${vehicleRef.id}');
      
      if (willOwnerDrive) {
        print('👤 Owner indicated they will drive this vehicle');
        
        bool isDriverRegistered = await _isUserRegisteredAsDriver(ownerId);
        
        if (isDriverRegistered) {
          print('✅ Owner is registered as driver. Auto-assigning vehicle...');
          // Enforce one vehicle per driver - CHECK BEFORE ASSIGNMENT
          final alreadyHasVehicle = await _driverHasVehicle(ownerId);
          if (alreadyHasVehicle) {
            print('⚠️ Owner already has a vehicle. Marking this vehicle for auto-assignment to next driver.');
            // Mark vehicle for auto-assignment to next driver instead of throwing error
            await vehicleRef.update({
              'pendingAssignment': true,
              'pendingOwnerAssignment': false,
            });
            
            // Return special Vehicle object indicating it needs auto-assignment
            return Vehicle(
              id: vehicleRef.id,
              make: make,
              model: model,
              year: year,
              licensePlate: licensePlate,
              ownerId: ownerId,
              assignedDriverId: null, // Not assigned
              status: 'Offline',
              alertness: 0,
              type: type,
            );
          }
          
          await assignVehicleToDriver(
            vehicleId: vehicleRef.id,
            driverId: ownerId,
            driverEmail: ownerEmail,
          );
          
          print('✅ Vehicle auto-assigned to owner-driver!');
          return Vehicle(
            id: vehicleRef.id,
            make: make,
            model: model,
            year: year,
            licensePlate: licensePlate,
            ownerId: ownerId,
            assignedDriverId: ownerId,
            status: 'Active',
            alertness: 0,
            type: type,
          );
        } else {
          print('❌ Owner is NOT registered as driver - needs driver signup');
          // Vehicle is created and will be assigned when owner completes driver signup
          return null;
        }
      } else {
        print('📋 Vehicle added without driver - will be assigned to next driver signup');
        // Vehicle created successfully, will be auto-assigned to next driver
        return Vehicle(
          id: vehicleRef.id,
          make: make,
          model: model,
          year: year,
          licensePlate: licensePlate,
          ownerId: ownerId,
          status: 'Offline',
          alertness: 0,
          type: type,
        );
      }
    } catch (e) {
      print('❌ Error adding vehicle: $e');
      rethrow;
    }
  }

  /// Check if user is registered as driver
  Future<bool> _isUserRegisteredAsDriver(String userId) async {
    try {
      print('🔍 Checking if user $userId is registered as driver...');
      
      DocumentSnapshot userDoc = 
          await _firestore.collection('users').doc(userId).get();
      
      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        List<String> roles = List<String>.from(data['roles'] ?? []);
        bool isDriver = roles.contains('driver');
        
        print(isDriver ? '✅ User is a driver' : '❌ User is not a driver');
        return isDriver;
      }
      
      print('❌ User document not found');
      return false;
    } catch (e) {
      print('❌ Error checking driver registration: $e');
      return false;
    }
  }

  /// Assign vehicle to driver
  Future<void> assignVehicleToDriver({
    required String vehicleId,
    required String driverId,
    required String driverEmail,
  }) async {
    try {
      print('🔗 Assigning vehicle $vehicleId to driver $driverId');

      // Enforce one vehicle per driver
      final alreadyHasVehicle = await _driverHasVehicle(driverId);
      if (alreadyHasVehicle) {
        throw Exception('Driver already has a vehicle assigned');
      }
      
      DocumentSnapshot driverDoc = 
          await _firestore.collection('users').doc(driverId).get();
      String driverName = 'Unknown Driver';
      if (driverDoc.exists) {
        Map<String, dynamic> data = driverDoc.data() as Map<String, dynamic>;
        // Try 'name', then combine first/last, then email, then fallback
        if (data.containsKey('name') && data['name'] != null && data['name'].toString().isNotEmpty) {
          driverName = data['name'];
        } else if (data['firstName'] != null && data['lastName'] != null) {
          driverName = '${data['firstName']} ${data['lastName']}';
        } else {
          driverName = data['email'] ?? 'Unknown Driver';
        }
      }
      
      await _firestore.collection('vehicles').doc(vehicleId).update({
        'assignedDriverId': driverId,
        'assignedDriverEmail': driverEmail,
        'driverName': driverName,
        'assignedAt': FieldValue.serverTimestamp(),
        'status': 'Active',
        'pendingAssignment': false,
        'pendingOwnerAssignment': false, // Clear this flag too
        'lastUpdate': DateTime.now().toString(),
      });

      await _firestore.collection('vehicleAssignments').add({
        'vehicleId': vehicleId,
        'driverId': driverId,
        'driverEmail': driverEmail,
        'driverName': driverName,
        'assignedAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      print('✅ Vehicle assigned to driver successfully!');
    } catch (e) {
      print('❌ Error assigning vehicle: $e');
      rethrow;
    }
  }

  /// CRITICAL: Assign vehicles specifically waiting for THIS owner to become a driver
  /// This is called when owner completes driver registration
  Future<List<String>> assignOwnerPendingVehicles(
    String ownerId, 
    String ownerEmail,
  ) async {
    try {
      print('🎯 Looking for vehicles waiting for owner $ownerId to become a driver');
      
      // If owner already has a vehicle, do not assign more
      if (await _driverHasVehicle(ownerId)) {
        print('⚠️ Owner already has an assigned vehicle. Skipping auto-assign.');
        return [];
      }

      // Find ALL vehicles owned by this user that are waiting for them to become a driver
      QuerySnapshot ownerPendingVehicles = await _firestore
          .collection('vehicles')
          .where('ownerId', isEqualTo: ownerId)
          .where('pendingOwnerAssignment', isEqualTo: true)
          .where('assignedDriverId', isNull: true)
          .get();

      List<String> assignedVehicleIds = [];

      if (ownerPendingVehicles.docs.isNotEmpty) {
        print('✅ Found ${ownerPendingVehicles.docs.length} vehicle(s) waiting for owner');
        
        // Assign ALL vehicles that were waiting for this owner
        for (var doc in ownerPendingVehicles.docs) {
          String vehicleId = doc.id;
          
          await assignVehicleToDriver(
            vehicleId: vehicleId,
            driverId: ownerId,
            driverEmail: ownerEmail,
          );
          
          assignedVehicleIds.add(vehicleId);
          print('✅ Assigned vehicle $vehicleId to owner-driver');
        }
        
        return assignedVehicleIds;
      }

      print('⚠️ No vehicles waiting for this owner');
      return [];
    } catch (e) {
      print('❌ Error assigning owner pending vehicles: $e');
      return [];
    }
  }

  /// Auto-assign general pending vehicles to new driver during signup
  /// This is for vehicles where owner said "No, I won't drive"
  Future<bool> assignGeneralPendingVehiclesToNewDriver(
    String driverId, 
    String driverEmail,
  ) async {
    try {
      print('🚗 Looking for general pending vehicles for new driver: $driverId');

      // Enforce one vehicle per driver
      if (await _driverHasVehicle(driverId)) {
        print('⚠️ Driver already has an assigned vehicle. Skipping auto-assign.');
        return false;
      }
      
      // Find vehicles with pendingAssignment=true (owner said they won't drive)
      QuerySnapshot unassignedVehicles = await _firestore
          .collection('vehicles')
          .where('pendingAssignment', isEqualTo: true)
          .orderBy('createdAt', descending: false) // Oldest first
          .get();
        
      // Filter for vehicles without an assigned driver
      var availableVehicles = unassignedVehicles.docs.where((doc) {
        var data = doc.data() as Map<String, dynamic>;
        return data['assignedDriverId'] == null || data['assignedDriverId'] == '';
      }).toList();

      if (availableVehicles.isNotEmpty) {
        String vehicleId = availableVehicles.first.id;      
        await assignVehicleToDriver(
          vehicleId: vehicleId,
          driverId: driverId,
          driverEmail: driverEmail,
        );
        
        print('✅ Assigned general pending vehicle to new driver: $vehicleId');
        return true;
      }

      print('⚠️ No general pending vehicles found for assignment');
      return false;
    } catch (e) {
      print('❌ Error assigning general pending vehicles: $e');
      return false;
    }
  }

  /// Get all pending (unassigned) vehicles
  Future<List<Vehicle>> getPendingVehicles() async {
    try {
      print('🚗 Fetching pending vehicles');
      
      QuerySnapshot snapshot = await _firestore
          .collection('vehicles')
          .where('assignedDriverId', isNull: true)
          .get();

      List<Vehicle> vehicles = snapshot.docs
          .where((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return data['pendingAssignment'] == true || 
                   data['pendingOwnerAssignment'] == true;
          })
          .map((doc) => Vehicle.fromMap({
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          }))
          .toList();

      print('✅ Found ${vehicles.length} pending vehicles');
      return vehicles;
    } catch (e) {
      print('❌ Error fetching pending vehicles: $e');
      return [];
    }
  }

  /// True if there is at least one general pending vehicle waiting for ANY driver.
  /// These vehicles are already admin-approved and sit in the general assignment pool.
  Stream<bool> hasGeneralPendingVehiclesStream() {
    try {
      return _firestore
          .collection('vehicles')
          .where('assignedDriverId', isNull: true)
          .where('pendingAssignment', isEqualTo: true)
          .snapshots()
          .map((snap) => snap.docs.isNotEmpty);
    } catch (_) {
      return Stream.value(false);
    }
  }

  /// True if there is at least one pending vehicle waiting specifically for THIS owner to become driver.
  Stream<bool> hasOwnerPendingVehiclesStream(String ownerId) {
    try {
      return _firestore
          .collection('vehicles')
          .where('ownerId', isEqualTo: ownerId)
          .where('assignedDriverId', isNull: true)
          .where('pendingOwnerAssignment', isEqualTo: true)
          .snapshots()
          .map((snap) => snap.docs.isNotEmpty);
    } catch (_) {
      return Stream.value(false);
    }
  }

  /// Get vehicles assigned to driver
  Future<List<Vehicle>> getAssignedVehiclesForDriver(String driverId) async {
    try {
      print('🚗 Fetching vehicles for driver: $driverId');
      
      QuerySnapshot snapshot = await _firestore
          .collection('vehicles')
          .where('assignedDriverId', isEqualTo: driverId)
          .get();

      List<Vehicle> vehicles = snapshot.docs
          .map((doc) => Vehicle.fromMap({
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          }))
          .toList();

      print('✅ Found ${vehicles.length} vehicles for driver');
      return vehicles;
    } catch (e) {
      print('❌ Error fetching driver vehicles: $e');
      return [];
    }
  }

  /// Get all vehicles for owner
  Future<List<Vehicle>> getVehiclesForOwner(String ownerId) async {
    try {
      print('🚗 Fetching vehicles for owner: $ownerId');
      
      QuerySnapshot snapshot = await _firestore
          .collection('vehicles')
          .where('ownerId', isEqualTo: ownerId)
          .get();

      List<Vehicle> vehicles = snapshot.docs
          .map((doc) => Vehicle.fromMap({
            'id': doc.id,
            ...doc.data() as Map<String, dynamic>,
          }))
          .toList();

      print('✅ Found ${vehicles.length} vehicles for owner');
      return vehicles;
    } catch (e) {
      print('❌ Error fetching owner vehicles: $e');
      return [];
    }
  }

  /// Get single vehicle stream for driver (returns first vehicle)
  Stream<Vehicle?> getVehicleByDriverStream(String driverId) {
    try {
      print('📡 Streaming vehicle for driver: $driverId');
      
      return _firestore
          .collection('vehicles')
          .where('assignedDriverId', isEqualTo: driverId)
          .limit(1)
          .snapshots()
          .map((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          Vehicle vehicle = Vehicle.fromMap({
            'id': snapshot.docs.first.id,
            ...snapshot.docs.first.data() as Map<String, dynamic>,
          });
          print('✅ Driver vehicle stream updated');
          return vehicle;
        }
        print('⚠️ No vehicle found for driver');
        return null;
      });
    } catch (e) {
      print('❌ Error getting driver vehicle stream: $e');
      return Stream.value(null);
    }
  }

  /// Get vehicles stream for owner (returns list)
  Stream<List<Vehicle>> getVehiclesByOwnerStream(String ownerId) {
    try {
      print('📡 Streaming vehicles for owner: $ownerId');
      
      return _firestore
          .collection('vehicles')
          .where('ownerId', isEqualTo: ownerId)
          .snapshots()
          .map((snapshot) {
        List<Vehicle> vehicles = snapshot.docs
            .map((doc) => Vehicle.fromMap({
              'id': doc.id,
              ...doc.data() as Map<String, dynamic>,
            }))
            .toList();
        
        print('✅ Owner vehicles stream: ${vehicles.length} vehicles');
        return vehicles;
      });
    } catch (e) {
      print('❌ Error getting owner vehicle stream: $e');
      return Stream.value([]);
    }
  }

  /// Update vehicle status
  Future<void> updateVehicleStatus(String vehicleId, String status) async {
    try {
      print('🔄 Updating vehicle $vehicleId status to: $status');
      
      await _firestore.collection('vehicles').doc(vehicleId).update({
        'status': status,
        'lastUpdate': DateTime.now().toString(),
      });

      print('✅ Vehicle status updated');
    } catch (e) {
      print('❌ Error updating vehicle status: $e');
      rethrow;
    }
  }

  /// Update vehicle alertness (0-100)
  Future<void> updateVehicleAlertness(String vehicleId, int alertness) async {
    try {
      print('🔄 Updating vehicle $vehicleId alertness to: $alertness%');
      
      await _firestore.collection('vehicles').doc(vehicleId).update({
        'alertness': alertness,
        'lastUpdate': DateTime.now().toString(),
      });

      print('✅ Vehicle alertness updated');
    } catch (e) {
      print('❌ Error updating vehicle alertness: $e');
      rethrow;
    }
  }

  /// Update vehicle location
  Future<void> updateVehicleLocation(String vehicleId, String location) async {
    try {
      print('📍 Updating vehicle $vehicleId location to: $location');
      
      await _firestore.collection('vehicles').doc(vehicleId).update({
        'location': location,
        'lastUpdate': DateTime.now().toString(),
      });

      print('✅ Vehicle location updated');
    } catch (e) {
      print('❌ Error updating vehicle location: $e');
      rethrow;
    }
  }

  /// Get vehicle by ID
  Future<Vehicle?> getVehicleById(String vehicleId) async {
    try {
      print('🔍 Fetching vehicle: $vehicleId');
      
      DocumentSnapshot doc = 
          await _firestore.collection('vehicles').doc(vehicleId).get();
      
      if (doc.exists) {
        Vehicle vehicle = Vehicle.fromMap({
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>,
        });
        
        print('✅ Vehicle found: ${vehicle.make} ${vehicle.model}');
        return vehicle;
      }
      
      print('❌ Vehicle not found');
      return null;
    } catch (e) {
      print('❌ Error fetching vehicle: $e');
      return null;
    }
  }

  /// Delete vehicle
  Future<void> deleteVehicle(String vehicleId) async {
    try {
      print('🗑️ Deleting vehicle: $vehicleId');
      
      await _firestore.collection('vehicles').doc(vehicleId).delete();
      
      // Also delete assignment records
      QuerySnapshot assignments = await _firestore
          .collection('vehicleAssignments')
          .where('vehicleId', isEqualTo: vehicleId)
          .get();
      
      for (var doc in assignments.docs) {
        await doc.reference.delete();
      }
      
      print('✅ Vehicle deleted successfully');
    } catch (e) {
      print('❌ Error deleting vehicle: $e');
      rethrow;
    }
  }

  /// Unassign vehicle from driver
  Future<void> unassignVehicleFromDriver(String vehicleId) async {
    try {
      print('🔓 Unassigning vehicle: $vehicleId');
      
      await _firestore.collection('vehicles').doc(vehicleId).update({
        'assignedDriverId': FieldValue.delete(),
        'assignedDriverEmail': FieldValue.delete(),
        'driverName': FieldValue.delete(),
        'status': 'Offline',
        'pendingAssignment': true, // Mark as pending again
      });

      // Update assignment record status
      QuerySnapshot assignments = await _firestore
          .collection('vehicleAssignments')
          .where('vehicleId', isEqualTo: vehicleId)
          .where('status', isEqualTo: 'active')
          .get();
      
      for (var doc in assignments.docs) {
        await doc.reference.update({
          'status': 'inactive',
          'unassignedAt': FieldValue.serverTimestamp(),
        });
      }

      print('✅ Vehicle unassigned successfully');
    } catch (e) {
      print('❌ Error unassigning vehicle: $e');
      rethrow;
    }
  }
}