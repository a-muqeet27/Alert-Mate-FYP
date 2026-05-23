import 'package:flutter/material.dart';

/// Vehicle type → make → models for owner add-vehicle dropdowns.
class VehicleCatalog {
  VehicleCatalog._();

  /// Outlined icons used for vehicle type across driver verification, owner, and admin UIs.
  static IconData iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'bus':
        return Icons.directions_bus_outlined;
      case 'van':
        return Icons.airport_shuttle_outlined;
      case 'truck':
        return Icons.local_shipping_outlined;
      case 'rickshaw':
        return Icons.moped_outlined;
      default:
        return Icons.directions_car_outlined;
    }
  }

  static IconData iconForFilterOption(String option) {
    if (option == 'All Types') return Icons.category_outlined;
    return iconForType(option);
  }

  static Widget dropdownMenuLabel(
    String label, {
    IconData? icon,
    Color? iconColor,
    double iconSize = 18,
  }) {
    return Row(
      children: [
        Icon(
          icon ?? iconForFilterOption(label),
          size: iconSize,
          color: iconColor,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }

  static const List<String> vehicleTypes = [
    'Car',
    'Bus',
    'Van',
    'Truck',
    'Rickshaw',
  ];

  static final Map<String, Map<String, List<String>>> _byType = {
    'Car': {
      'Toyota': [
        'Corolla',
        'Yaris',
        'Camry',
        'Prius',
        'Aqua',
        'Vitz',
        'Passo',
        'Corolla Cross',
        'Fortuner',
        'Prado',
        'Land Cruiser',
        'Hilux',
      ],
      'Honda': [
        'City',
        'Civic',
        'Accord',
        'HR-V',
        'BR-V',
        'Vezel',
        'Fit',
        'N-One',
        'N-WGN',
      ],
      'Suzuki': [
        'Alto',
        'Cultus',
        'Swift',
        'Wagon R',
        'Mehran',
        'Baleno',
        'Liana',
        'Ciaz',
      ],
      'Daihatsu': [
        'Mira',
        'Move',
        'Tanto',
        'Boon',
        'Esse',
        'Cast',
        'Rocky',
        'Terios',
      ],
      'Nissan': [
        'Dayz',
        'Note',
        'March',
        'Sunny',
        'Altima',
        'Juke',
        'X-Trail',
        'Patrol',
      ],
      'Hyundai': [
        'Elantra',
        'Sonata',
        'Tucson',
        'Santa Fe',
        'Palisade',
        'i10',
        'i20',
      ],
      'KIA': [
        'Picanto',
        'Rio',
        'Cerato',
        'Optima',
        'Sportage',
        'Stonic',
        'Sorento',
      ],
      'Changan': [
        'Alsvin',
        'Oshan X7',
        'UNI-T',
        'UNI-K',
      ],
      'MG': [
        'MG 5',
        'MG GT',
        'MG HS',
        'MG ZS',
        'MG ZS EV',
      ],
      'Haval': [
        'H6',
        'H6 HEV',
        'Jolion',
      ],
    },
    'Bus': {
      'Toyota': ['Coaster'],
      'Hyundai': ['County', 'Universe'],
      'Hino': ['AK Series (e.g. AK1J, AK8J)'],
      'Daewoo': ['Daewoo Express buses'],
    },
    'Van': {
      'Toyota': ['Hiace', 'Innova', 'Avanza', 'Veloz'],
      'Suzuki': ['Bolan', 'Every'],
      'Changan': ['Karvaan'],
      'Hyundai': ['Staria', 'H-100 (Porter)'],
      'Nissan': ['Caravan', 'NV200'],
      'KIA': ['Carnival'],
    },
    'Truck': {
      'Toyota': ['Hilux Revo / Rocco'],
      'Suzuki': ['Ravi'],
      'Hyundai': ['Porter H-100'],
      'Isuzu': ['D-Max', 'NPR Series'],
      'FAW': ['Carrier', 'V2'],
      'Hino': ['300 Series', '500 Series'],
      'JAC': ['T9 Hunter'],
      'Changan': ['M9 Sherpa', 'Karvaan (cargo)'],
    },
    'Rickshaw': {
      'Sazgar': ['4-Stroke Rickshaw', 'Loader Rickshaw'],
      'United Auto': ['Auto Rickshaw', 'Cargo Rickshaw'],
      'Road Prince': ['Passenger Rickshaw', 'Loader'],
      'Qingqi': ['Classic Qingqi Rickshaw'],
      'Tez Raftar': ['Passenger variant', 'Loader variant'],
    },
  };

  static List<String> makesFor(String vehicleType) {
    final map = _byType[vehicleType];
    if (map == null) return [];
    final list = map.keys.toList()..sort();
    return list;
  }

  static List<String> modelsFor(String vehicleType, String make) {
    final map = _byType[vehicleType];
    if (map == null) return [];
    return List<String>.from(map[make] ?? []);
  }

  static String? defaultMake(String vehicleType) {
    final m = makesFor(vehicleType);
    return m.isEmpty ? null : m.first;
  }

  static String? defaultModel(String vehicleType, String make) {
    final m = modelsFor(vehicleType, make);
    return m.isEmpty ? null : m.first;
  }
}
