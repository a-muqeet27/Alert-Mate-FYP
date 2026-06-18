import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/vehicle_catalog.dart';
import '../models/user.dart';
import '../services/owner_vehicle_submission_service.dart';
import '../services/vehicle_service.dart';
import 'owner_form_dialog_ui.dart';

class VehicleBookPdfPick {
  final Uint8List bytes;
  final String fileName;

  const VehicleBookPdfPick({
    required this.bytes,
    required this.fileName,
  });
}

typedef VehicleBookPdfPicker = Future<VehicleBookPdfPick?> Function();

class OwnerAddVehicleDialog extends StatefulWidget {
  final User user;
  final VehicleService vehicleService;
  final OwnerVehicleSubmissionService submissionService;
  final VehicleBookPdfPicker pickVehicleBookPdf;

  const OwnerAddVehicleDialog({
    super.key,
    required this.user,
    required this.vehicleService,
    required this.submissionService,
    required this.pickVehicleBookPdf,
  });

  @override
  State<OwnerAddVehicleDialog> createState() => _OwnerAddVehicleDialogState();
}

class _OwnerAddVehicleDialogState extends State<OwnerAddVehicleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _yearCtrl;
  late final TextEditingController _plateCtrl;

  String _vehicleType = 'Car';
  String _make = VehicleCatalog.defaultMake('Car') ?? '';
  String _model = '';
  bool _willDrive = false;
  Uint8List? _vehicleBookBytes;
  String? _vehicleBookFileName;

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController();
    _plateCtrl = TextEditingController();
    if (_make.isNotEmpty) {
      _model = VehicleCatalog.defaultModel(_vehicleType, _make) ?? '';
    }
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  void _closeDialog() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final year = _yearCtrl.text.trim();
    final licensePlate = _plateCtrl.text.trim().toUpperCase();
    var willDrive = _willDrive;

    if (willDrive) {
      final existingVehicles =
          await widget.vehicleService.getVehiclesForOwner(widget.user.id);
      final alreadyDrivingVehicle = existingVehicles.any(
        (v) => v.assignedDriverId == widget.user.id,
      );

      if (alreadyDrivingVehicle) {
        final existingVehicle = existingVehicles.firstWhere(
          (v) => v.assignedDriverId == widget.user.id,
        );

        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Already Driving a Vehicle')),
              ],
            ),
            content: Text(
              'You are already assigned as the driver for:\n\n'
              '${existingVehicle.make} ${existingVehicle.model} (${existingVehicle.licensePlate})\n\n'
              'A driver can only be assigned to one vehicle at a time.\n\n'
              'Would you like to add this vehicle without assigning yourself as the driver? '
              'It will be available for other drivers.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Add Without Driving'),
              ),
            ],
          ),
        );

        if (proceed != true) return;
        willDrive = false;
      }
    }

    if (_vehicleBookBytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please upload the vehicle ID-card/book as a PDF.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirm = await OwnerFormDialogUi.showVehicleAdditionConfirmDialog(
      context,
      vehicleType: _vehicleType,
      make: _make,
      model: _model,
      year: year,
      licensePlate: licensePlate,
      willOwnerDrive: willDrive,
      vehicleBookFileName: _vehicleBookFileName,
    );

    if (!confirm || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    _closeDialog();

    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('Submitting vehicle for admin approval...')),
      );

      await widget.submissionService.submitVehicle(
        ownerId: widget.user.id,
        ownerEmail: widget.user.email,
        ownerName: widget.user.fullName.trim().isEmpty
            ? widget.user.email
            : widget.user.fullName,
        make: _make,
        model: _model,
        year: year,
        licensePlate: licensePlate,
        type: _vehicleType,
        willOwnerDrive: willDrive,
        vehicleBookBytes: _vehicleBookBytes!,
      );

      messenger.showSnackBar(
        SnackBar(
          content: const Text('Submitted! Admin will approve your vehicle.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OwnerFormDialogUi.themedDialog(
      title: 'Add New Vehicle',
      subtitle: 'Submit Vehicle Details for Admin Approval',
      icon: Icons.add_road_outlined,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _vehicleType,
              dropdownColor: Colors.white,
              decoration: OwnerFormDialogUi.fieldDecoration('Type *'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
              items: VehicleCatalog.vehicleTypes
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: VehicleCatalog.dropdownMenuLabel(
                        t,
                        iconColor: AppColors.primary.withValues(alpha: 0.85),
                      ),
                    ),
                  )
                  .toList(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Type is required';
                return null;
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _vehicleType = value;
                  final m = VehicleCatalog.defaultMake(value) ?? '';
                  _make = m;
                  _model =
                      m.isNotEmpty ? (VehicleCatalog.defaultModel(value, m) ?? '') : '';
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _make.isNotEmpty && VehicleCatalog.makesFor(_vehicleType).contains(_make)
                  ? _make
                  : null,
              dropdownColor: Colors.white,
              decoration: OwnerFormDialogUi.fieldDecoration('Make *'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
              items: VehicleCatalog.makesFor(_vehicleType)
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Make is required';
                return null;
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _make = value;
                  _model = VehicleCatalog.defaultModel(_vehicleType, value) ?? '';
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _model.isNotEmpty &&
                      VehicleCatalog.modelsFor(_vehicleType, _make).contains(_model)
                  ? _model
                  : null,
              dropdownColor: Colors.white,
              decoration: OwnerFormDialogUi.fieldDecoration('Model *'),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.primary),
              items: VehicleCatalog.modelsFor(_vehicleType, _make)
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text(m, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Model is required';
                return null;
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() => _model = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _yearCtrl,
              cursorColor: AppColors.primary,
              decoration: OwnerFormDialogUi.fieldDecoration('Year *'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Year is required';
                final yearInt = int.tryParse(value.trim());
                if (yearInt == null) return 'Year must be a valid number';
                final currentYear = DateTime.now().year;
                if (yearInt < 1900 || yearInt > currentYear + 1) {
                  return 'Year must be between 1900 and ${currentYear + 1}';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plateCtrl,
              cursorColor: AppColors.primary,
              decoration: OwnerFormDialogUi.fieldDecoration('License Plate *', hint: 'ABC-123'),
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9\-]')),
                _LicensePlateFormatter(),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'License plate is required';
                }
                final plate = value.trim().toUpperCase();
                if (!RegExp(r'^[A-Z]{3}-[0-9]{3}$').hasMatch(plate)) {
                  return 'License plate must be in format ABC-123';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            OwnerFormDialogUi.sectionTitle('Vehicle ID-Card/Book (PDF Only) *'),
            const SizedBox(height: 4),
            Text(
              'Upload your Vehicle Registration Book or ID-card as a PDF File.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Material(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () async {
                  final picked = await widget.pickVehicleBookPdf();
                  if (picked == null || !mounted) return;
                  setState(() {
                    _vehicleBookBytes = picked.bytes;
                    _vehicleBookFileName = picked.fileName;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _vehicleBookBytes != null
                          ? AppColors.success.withValues(alpha: 0.5)
                          : AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _vehicleBookBytes != null
                            ? Icons.picture_as_pdf
                            : Icons.picture_as_pdf_outlined,
                        color:
                            _vehicleBookBytes != null ? AppColors.success : AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Upload PDF Document',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (_vehicleBookFileName != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _vehicleBookFileName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        _vehicleBookBytes != null ? 'Change' : 'Choose PDF',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OwnerFormDialogUi.listPanel(
              child: CheckboxListTile(
                title: const Text('I will be Driving this Vehicle'),
                subtitle: const Text('Assign this Vehicle to Me After Approval'),
                value: _willDrive,
                onChanged: (value) {
                  final turningOn = value == true && _willDrive != true;
                  setState(() => _willDrive = value ?? false);

                  if (turningOn && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'You will need CNIC + license admin approval before driving.',
                        ),
                        backgroundColor: AppColors.primary,
                        duration: Duration(seconds: 4),
                      ),
                    );
                  }
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closeDialog,
          style: OwnerFormDialogUi.cancelButtonStyle,
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: OwnerFormDialogUi.primaryButtonStyle,
          onPressed: _submit,
          child: const Text('Submit for Approval'),
        ),
      ],
    );
  }
}

class _LicensePlateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase();

    String formatted = text.replaceAll(RegExp(r'[^A-Z0-9\-]'), '');

    if (formatted.length > 7) {
      formatted = formatted.substring(0, 7);
    }

    if (formatted.length > 3 && !formatted.contains('-')) {
      formatted = '${formatted.substring(0, 3)}-${formatted.substring(3)}';
    }

    if (formatted.contains('-')) {
      final parts = formatted.split('-');
      if (parts.length == 2) {
        final letters = parts[0].replaceAll(RegExp(r'[^A-Z]'), '');
        final digits = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
        formatted = '$letters-$digits';
      }
    } else if (formatted.length > 3) {
      final letters = formatted.substring(0, 3).replaceAll(RegExp(r'[^A-Z]'), '');
      final digits = formatted.substring(3).replaceAll(RegExp(r'[^0-9]'), '');
      formatted = '$letters-$digits';
    } else {
      formatted = formatted.replaceAll(RegExp(r'[^A-Z]'), '');
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
