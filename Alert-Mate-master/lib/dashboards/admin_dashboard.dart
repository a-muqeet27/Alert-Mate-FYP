import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user.dart';
import '../models/emergency_contact.dart';
import '../constants/app_colors.dart';
import '../widgets/shared/app_sidebar.dart';
import '../widgets/shared/live_map.dart';
import '../services/emergency_contact_service.dart';
import '../services/driver_document_submission_service.dart';
import '../models/driver_document_submission.dart';
import '../services/owner_vehicle_submission_service.dart';
import '../models/owner_vehicle_submission.dart';
import '../widgets/email_verified_guard.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminDashboard extends StatefulWidget {
  final User user;

  const AdminDashboard({Key? key, required this.user}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with TickerProviderStateMixin {
  int _selectedIndex = 0; // 0: Dashboard, 1: Emergency
  String _selectedRoleFilter = 'All Roles';
  String _userTypeFilter = 'All Users';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _userSearchController = TextEditingController();
  String _userSearchQuery = '';

  // Vehicle management state
  final TextEditingController _vehicleSearchController = TextEditingController();
  String _vehicleSearchQuery = '';
  String _vehicleTypeFilter = 'All Types';
  String _vehicleStatusFilter = 'All Statuses';

  final DriverDocumentSubmissionService _driverDocumentSubmissionService = DriverDocumentSubmissionService();
  final OwnerVehicleSubmissionService _ownerVehicleSubmissionService = OwnerVehicleSubmissionService();
  String? _processingSubmissionId;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _emergencyContactService = EmergencyContactService();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _userSearchController.dispose();
    _vehicleSearchController.dispose();
    super.dispose();
  }

  Widget _buildStaggeredItem(Widget child, int index) {
    final Animation<double> fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Interval(index * 0.1, 1.0, curve: Curves.easeOut),
      ),
    );
    final Animation<Offset> slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Interval(index * 0.1, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: child,
      ),
    );
  }
  // Emergency contacts service
  late EmergencyContactService _emergencyContactService;


  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: isMobile ? _buildMobileDrawer() : null,
      appBar: isMobile ? AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.black87),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Admin Dashboard',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Text(
                widget.user.firstName[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ) : null,
      body: EmailVerifiedGuard(
        enforceVerification: false,
        child: isMobile
            ? _selectedIndex == 0 ? _buildMainContent() : _buildEmergency()
            : Row(
                children: [
                  _buildSidebar(),
                  Expanded(
                    child: _selectedIndex == 0 ? _buildMainContent() : _buildEmergency(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: AppSidebar(
          role: 'admin',
          user: widget.user,
          selectedIndex: _selectedIndex,
          onMenuItemTap: (index) {
            setState(() => _selectedIndex = index);
            Navigator.pop(context);
          },
          menuItems: const [
            MenuItem(icon: Icons.dashboard_outlined, title: 'Dashboard'),
            MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
          ],
          accentColor: AppColors.primary,
          accentLightColor: AppColors.primaryLight,
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return AppSidebar(
      role: 'admin',
      user: widget.user,
      selectedIndex: _selectedIndex,
      onMenuItemTap: (index) => setState(() => _selectedIndex = index),
      menuItems: const [
        MenuItem(icon: Icons.dashboard_outlined, title: 'Dashboard'),
        MenuItem(icon: Icons.phone_outlined, title: 'Emergency'),
      ],
      accentColor: AppColors.primary,
      accentLightColor: AppColors.primaryLight,
    );
  }


  Widget _buildMainContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMobile) ...[
                  _buildStaggeredItem(
                    Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    0,
                  ),
                  SizedBox(height: isMobile ? 6 : 8),
                  _buildStaggeredItem(
                    Text(
                      'System overview and user management',
                      style: TextStyle(
                        fontSize: isMobile ? 13 : 16,
                        color: Colors.black54,
                      ),
                    ),
                    1,
                  ),
                ],
                const SizedBox(height: 32),
                _buildStaggeredItem(
                  _buildDynamicStats(isMobile),
                  2,
                ),
                const SizedBox(height: 32),
                _buildStaggeredItem(
                  const LiveMap(),
                  3,
                ),
                const SizedBox(height: 32),
                _buildStaggeredItem(_buildUserManagement(), 4),
                const SizedBox(height: 32),
                _buildStaggeredItem(_buildVehicleManagement(), 5),
                const SizedBox(height: 32),
                _buildStaggeredItem(_buildDocumentApproval(), 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergency() {
    final isMobile = MediaQuery.of(context).size.width < 768;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16.0 : 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Contacts',
              style: TextStyle(
                fontSize: isMobile ? 24 : 36,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: isMobile ? 6 : 8),
            Text(
              'Quick access to emergency services and contacts',
              style: TextStyle(
                fontSize: isMobile ? 13 : 16,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: isMobile ? 24 : 32),

            isMobile
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildEmergencyServiceCard('Police', '15', Icons.local_police, AppColors.police, AppColors.policeLight, isMobile),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEmergencyServiceCard('Ambulance', '1122', Icons.local_hospital, AppColors.ambulance, AppColors.ambulanceLight, isMobile),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEmergencyServiceCard('Fire Department', '16', Icons.local_fire_department, AppColors.fire, AppColors.fireLight, isMobile),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEmergencyServiceCard('Motorway Police', '130', Icons.car_crash, AppColors.motorway, AppColors.motorwayLight, isMobile),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildEmergencyServiceCard('Police', '15', Icons.local_police, AppColors.police, AppColors.policeLight, isMobile),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildEmergencyServiceCard('Ambulance', '1122', Icons.local_hospital, AppColors.ambulance, AppColors.ambulanceLight, isMobile),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEmergencyServiceCard('Fire Department', '16', Icons.local_fire_department, AppColors.fire, AppColors.fireLight, isMobile),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: _buildEmergencyServiceCard('Motorway Police', '130', Icons.car_crash, AppColors.motorway, AppColors.motorwayLight, isMobile),
                          ),
                        ],
                      ),
                    ],
                  ),
            SizedBox(height: isMobile ? 24 : 32),

            _buildEmergencyContactsTable(isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyServiceCard(String title, String number, IconData icon, Color color, Color bgColor, [bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: isMobile ? 56 : 64,
            height: isMobile ? 56 : 64,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: isMobile ? 28 : 32),
          ),
          SizedBox(height: isMobile ? 12 : 16),
          Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            number,
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final Uri url = Uri.parse('tel:$number');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not launch dialer')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContactsTable([bool isMobile = false]) {
    return StreamBuilder<List<EmergencyContact>>(
      stream: _emergencyContactService.getEmergencyContactsStream(widget.user.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text('Error loading contacts: ${snapshot.error}'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: EdgeInsets.all(isMobile ? 16 : 28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final contacts = snapshot.data ?? [];

        return Container(
          padding: EdgeInsets.all(isMobile ? 16 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Contacts',
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: isMobile ? 2 : 4),
                        Text(
                          'Manage your emergency contact list',
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: isMobile ? 8 : 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      _showContactDialog(context: context);
                    },
                    icon: Icon(Icons.add, size: isMobile ? 16 : 18),
                    label: Text('Add Contact', style: TextStyle(fontSize: isMobile ? 13 : 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 20,
                          vertical: isMobile ? 10 : 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isMobile ? 16 : 24),
              isMobile
                  ? contacts.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(isMobile ? 20 : 40),
                          child: Center(
                            child: Text(
                              'No emergency contacts added yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: contacts.map((contact) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildMobileContactCard(contact),
                              )).toList(),
                        )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: isMobile ? 0 : 800),
                        child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1.5),
                            1: FlexColumnWidth(1.2),
                            2: FlexColumnWidth(1.8),
                            3: FlexColumnWidth(1.0),
                            4: FlexColumnWidth(1.0),
                            5: FlexColumnWidth(0.8),
                            6: FlexColumnWidth(1.0),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              children: [
                                _buildTableHeader('Name', isMobile),
                                _buildTableHeader('Relationship', isMobile),
                                _buildTableHeader('Contact', isMobile),
                                _buildTableHeader('Priority', isMobile),
                                _buildTableHeader('Methods', isMobile),
                                _buildTableHeader('Status', isMobile),
                                _buildTableHeader('Actions', isMobile),
                              ],
                            ),
                            ...contacts.map((contact) => _buildEmergencyContactRow(contact, isMobile)),
                          ],
                        ),
                      ),
                    ),
              SizedBox(height: isMobile ? 16 : 20),
              Row(
                children: [
                  Icon(Icons.info_outline, size: isMobile ? 14 : 16, color: Colors.grey[600]),
                  SizedBox(width: isMobile ? 6 : 8),
                  Flexible(
                    child: Text(
                      'Last system test: Just now • ${contacts.length} active contacts',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileContactCard(EmergencyContact contact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              _buildContactActionsCell(contact, true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            contact.relationship,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.phone, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(contact.phone, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.email, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  contact.email,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPriorityBadgeCell(contact.priority, true),
              ),
              const SizedBox(width: 8),
              _buildStatusToggleCell(contact, true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 11 : 13,
          fontWeight: FontWeight.w600,
          color: Colors.black54,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 12 : 16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isMobile ? 12 : 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildContactInfoCell(String phone, String email, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 16,
          vertical: isMobile ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phone,
            style: TextStyle(
              fontSize: isMobile ? 12 : 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          if (email.isNotEmpty) ...[
            SizedBox(height: isMobile ? 2 : 4),
            Text(
              email,
              style: TextStyle(
                fontSize: isMobile ? 11 : 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPriorityBadgeCell(String priority, [bool isMobile = false]) {
    final isPrimary = priority == 'primary';
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 12,
            vertical: isMobile ? 4 : 6),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.red : const Color(0xFFFF6F00),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          priority,
          style: TextStyle(
            fontSize: isMobile ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMethodsCell(List<dynamic> methods, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (methods.contains('call'))
            Icon(Icons.phone, size: isMobile ? 16 : 18, color: Colors.green[600]),
          if (methods.contains('call')) SizedBox(width: isMobile ? 4 : 6),
          if (methods.contains('sms'))
            Icon(Icons.message, size: isMobile ? 16 : 18, color: Colors.blue[600]),
          if (methods.contains('sms')) SizedBox(width: isMobile ? 4 : 6),
          if (methods.contains('email'))
            Icon(Icons.email, size: isMobile ? 16 : 18, color: Colors.grey[600]),
        ],
      ),
    );
  }

  Future<void> _showContactDialog({required BuildContext context, EmergencyContact? contact}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: contact?.name ?? '');
    final relationshipController = TextEditingController(text: contact?.relationship ?? '');
    final phoneController = TextEditingController(text: contact?.phone ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    String priority = contact?.priority ?? 'primary';
    final methods = Set<String>.from(contact?.methods ?? <String>{'call'});
    bool enabled = contact?.enabled ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(contact == null ? 'Add Contact' : 'Edit Contact'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: relationshipController,
                      decoration: const InputDecoration(labelText: 'Relationship'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    TextFormField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email (optional)'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Priority:'),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: priority,
                          items: const [
                            DropdownMenuItem(value: 'primary', child: Text('Primary')),
                            DropdownMenuItem(value: 'secondary', child: Text('Secondary')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => priority = val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('call'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('call'); } else { methods.remove('call'); }
                                });
                              },
                            ),
                            const Text('Call'),
                          ]),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('sms'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('sms'); } else { methods.remove('sms'); }
                                });
                              },
                            ),
                            const Text('SMS'),
                          ]),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Checkbox(
                              value: methods.contains('email'),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) { methods.add('email'); } else { methods.remove('email'); }
                                });
                              },
                            ),
                            const Text('Email'),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Enabled'),
                        const SizedBox(width: 12),
                        Switch(
                          value: enabled,
                          onChanged: (val) {
                            setDialogState(() => enabled = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  if (methods.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Select at least one method')),
                    );
                    return;
                  }
                  
                  Navigator.pop(ctx);
                  
                  try {
                    if (contact == null) {
                      await _emergencyContactService.addEmergencyContact(
                        userId: widget.user.id,
                        userRole: 'admin',
                        contactData: {
                          'name': nameController.text.trim(),
                          'relationship': relationshipController.text.trim(),
                          'phone': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'priority': priority,
                          'methods': methods.toList(),
                          'enabled': enabled,
                        },
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contact added')),
                        );
                      }
                    } else {
                      await _emergencyContactService.updateEmergencyContact(
                        contactId: contact.id,
                        contactData: {
                          'name': nameController.text.trim(),
                          'relationship': relationshipController.text.trim(),
                          'phone': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'priority': priority,
                          'methods': methods.toList(),
                          'enabled': enabled,
                        },
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contact updated')),
                        );
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: Text(contact == null ? 'Add' : 'Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  TableRow _buildEmergencyContactRow(EmergencyContact contact, [bool isMobile = false]) {
    return TableRow(
      children: [
        _buildTableCell(contact.name, isMobile),
        _buildTableCell(contact.relationship, isMobile),
        _buildContactInfoCell(contact.phone, contact.email, isMobile),
        _buildPriorityBadgeCell(contact.priority, isMobile),
        _buildMethodsCell(contact.methods, isMobile),
        _buildStatusToggleCell(contact, isMobile),
        _buildContactActionsCell(contact, isMobile),
      ],
    );
  }

  Widget _buildStatusToggleCell(EmergencyContact contact, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 16,
          vertical: isMobile ? 0 : 12),
      child: Switch(
        value: contact.enabled,
        onChanged: (value) async {
          try {
            await _emergencyContactService.toggleContactEnabled(contact.id, value);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        },
        activeColor: const Color(0xFF2196F3),
      ),
    );
  }

  Widget _buildContactActionsCell(EmergencyContact contact, [bool isMobile = false]) {
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 8,
          vertical: isMobile ? 0 : 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.edit_outlined, size: isMobile ? 18 : 20),
            onPressed: () {
              _showContactDialog(context: context, contact: contact);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          SizedBox(width: isMobile ? 4 : 8),
          IconButton(
            icon: Icon(Icons.delete_outline, size: isMobile ? 18 : 20),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Contact'),
                  content: Text('Are you sure you want to delete ${contact.name} from emergency contacts? This action cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                try {
                  await _emergencyContactService.deleteEmergencyContact(contact.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${contact.name} removed')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }



  Widget _buildStatCard(String title, String value, String subtitle,
      IconData icon, Color valueColor, Color subtitleColor, [bool isMobile = false]) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: Colors.grey[400], size: 20),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 12),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              color: subtitleColor,
            ),
          ),
        ],
      ),
    );
  }

  // --- Dynamic Stats Section ---
  Widget _buildDynamicStats(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, usersSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('vehicles').snapshots(),
          builder: (context, vehiclesSnapshot) {
            // Calculate user counts
            int totalUsers = 0;
            int driverCount = 0;
            int ownerCount = 0;

            if (usersSnapshot.hasData) {
              final users = usersSnapshot.data!.docs;
              totalUsers = users.length;
              for (var doc in users) {
                final data = doc.data() as Map<String, dynamic>;
                final roles = data['roles'] as List<dynamic>? ?? [];
                final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
                if (roles.map((r) => r.toString().toLowerCase()).contains('driver') || activeRole == 'driver') driverCount++;
                if (roles.map((r) => r.toString().toLowerCase()).contains('owner') || activeRole == 'owner') ownerCount++;
              }
            }

            // Calculate vehicle stats
            int activeVehicles = 0;
            int alertsCount = 0;

            if (vehiclesSnapshot.hasData) {
              for (var doc in vehiclesSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final status = (data['status'] as String? ?? '').toLowerCase();
                final alertness = data['alertness'] as int? ?? 0;
                final assignedDriverId = data['assignedDriverId'] as String?;
                if (assignedDriverId != null && assignedDriverId.isNotEmpty) activeVehicles++;
                if (status == 'critical' || (alertness < 50 && alertness > 0)) alertsCount++;
              }
            }

            // Determine display value based on dropdown
            String usersValue;
            String usersSubtitle;
            if (_userTypeFilter == 'Drivers') {
              usersValue = driverCount.toString();
              usersSubtitle = 'Registered drivers';
            } else if (_userTypeFilter == 'Owners') {
              usersValue = ownerCount.toString();
              usersSubtitle = 'Registered owners';
            } else {
              usersValue = totalUsers.toString();
              usersSubtitle = 'Registered users';
            }

            final isLoading = !usersSnapshot.hasData || !vehiclesSnapshot.hasData;

            if (isMobile) {
              return Column(
                children: [
                  _buildTotalUsersCard(isLoading ? '...' : usersValue, usersSubtitle, isMobile),
                  const SizedBox(height: 12),
                  _buildStatCard('Active Vehicles', isLoading ? '...' : activeVehicles.toString(), 'Vehicles with drivers', Icons.directions_car, Colors.black87, AppColors.success, isMobile),
                  const SizedBox(height: 12),
                  _buildStatCard('Alerts', isLoading ? '...' : alertsCount.toString(), 'Require attention', Icons.warning_amber, Colors.black87, AppColors.warning, isMobile),
                ],
              );
            } else {
              return Row(
                children: [
                  Expanded(child: _buildTotalUsersCard(isLoading ? '...' : usersValue, usersSubtitle, isMobile)),
                  const SizedBox(width: 20),
                  Expanded(child: _buildStatCard('Active Vehicles', isLoading ? '...' : activeVehicles.toString(), 'Vehicles with drivers', Icons.directions_car, Colors.black87, AppColors.success, isMobile)),
                  const SizedBox(width: 20),
                  Expanded(child: _buildStatCard('Alerts', isLoading ? '...' : alertsCount.toString(), 'Require attention', Icons.warning_amber, Colors.black87, AppColors.warning, isMobile)),
                ],
              );
            }
          },
        );
      },
    );
  }

  Widget _buildTotalUsersCard(String value, String subtitle, bool isMobile) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _userTypeFilter,
                    underline: const SizedBox(),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'All Users', child: Text('All Users')),
                      DropdownMenuItem(value: 'Drivers', child: Text('Drivers')),
                      DropdownMenuItem(value: 'Owners', child: Text('Owners')),
                    ],
                    onChanged: (val) => setState(() => _userTypeFilter = val!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.people, color: Colors.grey[400], size: 20),
            ],
          ),
          SizedBox(height: isMobile ? 10 : 12),
          Text(
            value,
            style: TextStyle(
              fontSize: isMobile ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: isMobile ? 6 : 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isMobile ? 12 : 13,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: Format time ago ---
  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  Widget _buildUserManagement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'User Management',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'View registered users and their roles',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  return constraints.maxWidth < 600
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _userSearchController,
                              decoration: InputDecoration(
                                hintText: 'Search users...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _userSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _userSearchController.clear();
                                          setState(() => _userSearchQuery = '');
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              onChanged: (value) => setState(() => _userSearchQuery = value.trim()),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedRoleFilter,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              items: ['All Roles', 'Admin', 'Driver', 'Owner']
                                  .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                                  .toList(),
                              onChanged: (value) => setState(() => _selectedRoleFilter = value!),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _userSearchController,
                                decoration: InputDecoration(
                                  hintText: 'Search users...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: _userSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            _userSearchController.clear();
                                            setState(() => _userSearchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onChanged: (value) => setState(() => _userSearchQuery = value.trim()),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButton<String>(
                                value: _selectedRoleFilter,
                                items: ['All Roles', 'Admin', 'Driver', 'Owner']
                                    .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                                    .toList(),
                                onChanged: (value) => setState(() => _selectedRoleFilter = value!),
                                underline: const SizedBox(),
                              ),
                            ),
                          ],
                        );
                },
              ),
              const SizedBox(height: 24),
              _buildUserTable(),
            ],
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            return constraints.maxWidth < 900
                ? Column(
                    children: [
                      _buildUserRoleDistribution(),
                      const SizedBox(height: 24),
                      _buildRecentActivities(),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildUserRoleDistribution()),
                      const SizedBox(width: 24),
                      Expanded(child: _buildRecentActivities()),
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _buildUserTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No users found', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        var users = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        // Apply role filter
        if (_selectedRoleFilter != 'All Roles') {
          final filterRole = _selectedRoleFilter.toLowerCase();
          users = users.where((data) {
            final roles = (data['roles'] as List<dynamic>?)?.map((r) => r.toString().toLowerCase()).toList() ?? [];
            final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
            return roles.contains(filterRole) || activeRole == filterRole;
          }).toList();
        }

        // Apply search filter
        if (_userSearchQuery.isNotEmpty) {
          final query = _userSearchQuery.toLowerCase();
          users = users.where((data) {
            final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.toLowerCase();
            final email = (data['email'] as String? ?? '').toLowerCase();
            return name.contains(query) || email.contains(query);
          }).toList();
        }

        if (users.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No users match the current filters', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            if (isMobile) {
              return Column(
                children: users.map((user) => _buildMobileUserCard(user)).toList(),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 800),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2.5),
                    2: FlexColumnWidth(1.5),
                    3: FlexColumnWidth(1.5),
                    4: FlexColumnWidth(1.5),
                    5: FlexColumnWidth(1.2),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Role', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Joined', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                      ],
                    ),
                    ...users.map((user) {
                      final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
                      final email = user['email'] as String? ?? '';
                      final activeRole = user['activeRole'] as String? ?? user['role'] as String? ?? 'N/A';
                      final isActive = user['isActive'] as bool? ?? true;
                      final createdAt = user['createdAt'] is Timestamp
                          ? (user['createdAt'] as Timestamp).toDate()
                          : null;
                      final joinedText = createdAt != null ? _formatTimeAgo(createdAt) : 'N/A';

                      return TableRow(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        children: [
                          _buildTableCell(name.isNotEmpty ? name : 'Unknown'),
                          _buildTableCell(email),
                          _buildRoleBadge(activeRole),
                          _buildStatusBadge(isActive ? 'Active' : 'Inactive'),
                          _buildTableCell(joinedText),
                          _buildUserActionsCell(user),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileUserCard(Map<String, dynamic> user) {
    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '';
    final activeRole = user['activeRole'] as String? ?? user['role'] as String? ?? 'N/A';
    final isActive = user['isActive'] as bool? ?? true;
    final createdAt = user['createdAt'] is Timestamp
        ? (user['createdAt'] as Timestamp).toDate()
        : null;
    final joinedText = createdAt != null ? _formatTimeAgo(createdAt) : 'N/A';

    final roleColors = {
      'driver': const Color(0xFF4CAF50),
      'owner': const Color(0xFF2196F3),
      'admin': const Color(0xFF9C27B0),
    };
    final roleColor = roleColors[activeRole.toLowerCase()] ?? Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: roleColor.withOpacity(0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Unknown',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF4CAF50) : Colors.grey[400],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Inactive',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  activeRole,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              if (phone.isNotEmpty) ...[
                Icon(Icons.phone, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Flexible(child: Text(phone, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
              ],
              const Spacer(),
              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(joinedText, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => _showEditUserDialog(user),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 15, color: Color(0xFF2196F3)),
                      SizedBox(width: 4),
                      Text('Edit', style: TextStyle(fontSize: 12, color: Color(0xFF2196F3), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _confirmDeleteUser(user),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 15, color: Colors.red),
                      SizedBox(width: 4),
                      Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildRoleBadge(String role) {
    final colors = {
      'driver': const Color(0xFF4CAF50),
      'passenger': const Color(0xFFFF9800),
      'owner': const Color(0xFF2196F3),
      'admin': const Color(0xFF9C27B0),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors[role]!,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          role,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isActive = status == 'Active';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF4CAF50) : Colors.grey[400],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          status,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildUserActionsCell(Map<String, dynamic> user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2196F3)),
            tooltip: 'Edit user',
            onPressed: () => _showEditUserDialog(user),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete user',
            onPressed: () => _confirmDeleteUser(user),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final docId = user['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: User ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final firstNameCtrl = TextEditingController(text: user['firstName'] as String? ?? '');
    final lastNameCtrl = TextEditingController(text: user['lastName'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: user['phone'] as String? ?? '');
    String selectedRole = (user['activeRole'] as String? ?? user['role'] as String? ?? 'driver').toLowerCase();
    bool isActive = user['isActive'] as bool? ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Color(0xFF2196F3), size: 22),
                SizedBox(width: 8),
                Text('Edit User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: firstNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'First Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'First name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: lastNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Last Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Last name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: phoneCtrl,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: ['driver', 'owner', 'admin']
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(r[0].toUpperCase() + r.substring(1)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Account Active', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        Switch(
                          value: isActive,
                          onChanged: (val) => setDialogState(() => isActive = val),
                          activeColor: const Color(0xFF4CAF50),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.pop(ctx);
                  try {
                    await _firestore.collection('users').doc(docId).update({
                      'firstName': firstNameCtrl.text.trim(),
                      'lastName': lastNameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'activeRole': selectedRole,
                      'role': selectedRole,
                      'isActive': isActive,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User updated successfully'), backgroundColor: Color(0xFF4CAF50)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating user: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteUser(Map<String, dynamic> user) async {
    final docId = user['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: User ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final name = '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
    final email = user['email'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to delete this user?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isNotEmpty ? name : 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone. All user data will be permanently removed.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Also remove user from any assigned vehicles
        final vehicleSnapshot = await _firestore.collection('vehicles')
            .where('assignedDriverId', isEqualTo: docId)
            .get();
        for (var vDoc in vehicleSnapshot.docs) {
          await vDoc.reference.update({
            'assignedDriverId': null,
            'assignedDriverEmail': null,
            'driverName': null,
            'status': 'Offline',
          });
        }

        await _firestore.collection('users').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${name.isNotEmpty ? name : "User"} has been deleted'), backgroundColor: const Color(0xFF4CAF50)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting user: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildUserRoleDistribution() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').snapshots(),
      builder: (context, snapshot) {
        int driverCount = 0;
        int ownerCount = 0;
        int adminCount = 0;
        int totalCount = 0;

        if (snapshot.hasData) {
          totalCount = snapshot.data!.docs.length;
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final roles = (data['roles'] as List<dynamic>?)?.map((r) => r.toString().toLowerCase()).toList() ?? [];
            final activeRole = (data['activeRole'] as String? ?? data['role'] as String? ?? '').toLowerCase();
            if (roles.contains('driver') || activeRole == 'driver') driverCount++;
            if (roles.contains('owner') || activeRole == 'owner') ownerCount++;
            if (roles.contains('admin') || activeRole == 'admin') adminCount++;
          }
        }

        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Role Distribution',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Breakdown of $totalCount registered users',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              if (!snapshot.hasData)
                const Center(child: CircularProgressIndicator())
              else ...[
                _buildRoleRow('Drivers', driverCount, const Color(0xFF4CAF50)),
                _buildRoleRow('Owners', ownerCount, const Color(0xFF2196F3)),
                _buildRoleRow('Admins', adminCount, const Color(0xFF9C27B0)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoleRow(String role, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            role,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivities() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').orderBy('createdAt', descending: true).limit(3).snapshots(),
      builder: (context, usersSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('vehicles').orderBy('createdAt', descending: true).limit(3).snapshots(),
          builder: (context, vehiclesSnapshot) {
            // Build activity list from multiple sources
            final List<Map<String, dynamic>> activities = [];

            // User registrations
            if (usersSnapshot.hasData) {
              for (var doc in usersSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                final activeRole = data['activeRole'] as String? ?? data['role'] as String? ?? 'user';
                final createdAt = data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;
                activities.add({
                  'type': 'user_registered',
                  'icon': Icons.person_add_outlined,
                  'title': name.isNotEmpty ? name : 'New User',
                  'subtitle': '${activeRole[0].toUpperCase()}${activeRole.substring(1)} registered',
                  'time': createdAt,
                  'color': activeRole.toLowerCase() == 'driver'
                      ? const Color(0xFF4CAF50)
                      : activeRole.toLowerCase() == 'owner'
                          ? const Color(0xFF2196F3)
                          : const Color(0xFF9C27B0),
                });
              }
            }

            // Vehicle additions
            if (vehiclesSnapshot.hasData) {
              for (var doc in vehiclesSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final make = data['make'] as String? ?? '';
                final model = data['model'] as String? ?? '';
                final plate = data['licensePlate'] as String? ?? '';
                final createdAt = data['createdAt'] is Timestamp
                    ? (data['createdAt'] as Timestamp).toDate()
                    : null;
                activities.add({
                  'type': 'vehicle_added',
                  'icon': Icons.directions_car_outlined,
                  'title': '$make $model'.trim().isNotEmpty ? '$make $model'.trim() : 'New Vehicle',
                  'subtitle': 'Vehicle added ${plate.isNotEmpty ? "• $plate" : ""}',
                  'time': createdAt,
                  'color': const Color(0xFFFF9800),
                });
              }
            }

            // Sort by time descending, nulls last
            activities.sort((a, b) {
              final aTime = a['time'] as DateTime?;
              final bTime = b['time'] as DateTime?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

            // Take only first 5
            final recentActivities = activities.take(5).toList();

            return Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Activities',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Latest system activities',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),
                  if (!usersSnapshot.hasData && !vehiclesSnapshot.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (recentActivities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.history, size: 40, color: Colors.grey[400]),
                            const SizedBox(height: 8),
                            Text('No recent activities', style: TextStyle(color: Colors.grey[600])),
                          ],
                        ),
                      ),
                    )
                  else
                    ...recentActivities.map((activity) {
                      final timeText = activity['time'] != null
                          ? _formatTimeAgo(activity['time'] as DateTime)
                          : 'Unknown';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildActivityItem(
                          activity['icon'] as IconData,
                          activity['title'] as String,
                          '${activity['subtitle']} • $timeText',
                          activity['color'] as Color,
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActivityItem(IconData icon, String title, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =============================================
  // VEHICLE MANAGEMENT SECTION
  // =============================================
  Widget _buildVehicleManagement() {
    final narrow = MediaQuery.of(context).size.width < 600;
    final pad = narrow ? 12.0 : 32.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vehicle Management',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'View and manage registered vehicles',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  return constraints.maxWidth < 900
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _vehicleSearchController,
                              decoration: InputDecoration(
                                hintText: 'Search vehicles...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: _vehicleSearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _vehicleSearchController.clear();
                                          setState(() => _vehicleSearchQuery = '');
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                isDense: true,
                              ),
                              onChanged: (value) => setState(() => _vehicleSearchQuery = value.trim()),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _vehicleTypeFilter,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                isDense: true,
                              ),
                              items: ['All Types', 'Car', 'Bus', 'Van', 'Truck', 'Rickshaw']
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (value) => setState(() => _vehicleTypeFilter = value!),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _vehicleStatusFilter,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey[300]!),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                isDense: true,
                              ),
                              items: ['All Statuses', 'Active', 'Offline', 'Critical']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (value) => setState(() => _vehicleStatusFilter = value!),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: _vehicleSearchController,
                                decoration: InputDecoration(
                                  hintText: 'Search vehicles...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: _vehicleSearchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            _vehicleSearchController.clear();
                                            setState(() => _vehicleSearchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey[300]!),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                                onChanged: (value) => setState(() => _vehicleSearchQuery = value.trim()),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _vehicleTypeFilter,
                                  items: ['All Types', 'Car', 'Bus', 'Van', 'Truck', 'Rickshaw']
                                      .map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (value) => setState(() => _vehicleTypeFilter = value!),
                                  underline: const SizedBox(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _vehicleStatusFilter,
                                  items: ['All Statuses', 'Active', 'Offline', 'Critical']
                                      .map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                                      .toList(),
                                  onChanged: (value) => setState(() => _vehicleStatusFilter = value!),
                                  underline: const SizedBox(),
                                ),
                              ),
                            ),
                          ],
                        );
                },
              ),
              const SizedBox(height: 24),
              _buildVehicleTable(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleTable() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('vehicles').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No vehicles found', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        var vehicles = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['docId'] = doc.id;
          return data;
        }).toList();

        // Apply type filter
        if (_vehicleTypeFilter != 'All Types') {
          vehicles = vehicles.where((v) {
            final type = (v['type'] as String? ?? 'Car');
            return type == _vehicleTypeFilter;
          }).toList();
        }

        // Apply status filter
        if (_vehicleStatusFilter != 'All Statuses') {
          vehicles = vehicles.where((v) {
            final status = (v['status'] as String? ?? 'Offline');
            if (_vehicleStatusFilter == 'Active') {
              final assignedDriverId = v['assignedDriverId'] as String?;
              return assignedDriverId != null && assignedDriverId.isNotEmpty;
            }
            return status.toLowerCase() == _vehicleStatusFilter.toLowerCase();
          }).toList();
        }

        // Apply search
        if (_vehicleSearchQuery.isNotEmpty) {
          final query = _vehicleSearchQuery.toLowerCase();
          vehicles = vehicles.where((v) {
            final make = (v['make'] as String? ?? '').toLowerCase();
            final model = (v['model'] as String? ?? '').toLowerCase();
            final plate = (v['licensePlate'] as String? ?? '').toLowerCase();
            final driverName = (v['driverName'] as String? ?? '').toLowerCase();
            final ownerEmail = (v['ownerEmail'] as String? ?? '').toLowerCase();
            return make.contains(query) || model.contains(query) || plate.contains(query) || driverName.contains(query) || ownerEmail.contains(query);
          }).toList();
        }

        if (vehicles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('No vehicles match the current filters', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            if (isMobile) {
              return Column(
                children: vehicles.map((v) => _buildMobileVehicleCard(v)).toList(),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 900),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1.5),
                    4: FlexColumnWidth(1.2),
                    5: FlexColumnWidth(1.2),
                    6: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      ),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Vehicle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('License Plate', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Driver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Status', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Alertness', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54)),
                        ),
                      ],
                    ),
                    ...vehicles.map((v) {
                      final make = v['make'] as String? ?? '';
                      final model = v['model'] as String? ?? '';
                      final plate = v['licensePlate'] as String? ?? '';
                      final type = v['type'] as String? ?? 'Car';
                      final driverName = v['driverName'] as String?;
                      final status = v['status'] as String? ?? 'Offline';
                      final alertness = v['alertness'] as int? ?? 0;
                      final assignedDriverId = v['assignedDriverId'] as String?;
                      final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;

                      return TableRow(
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        children: [
                          _buildTableCell('$make $model'.trim()),
                          _buildTableCell(plate),
                          _buildVehicleTypeBadge(type),
                          _buildTableCell(hasDriver ? (driverName ?? 'Assigned') : 'Unassigned'),
                          _buildVehicleStatusBadge(status, hasDriver),
                          _buildAlertnessBadge(alertness),
                          _buildVehicleActionsCell(v),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileVehicleCard(Map<String, dynamic> vehicle) {
    final make = vehicle['make'] as String? ?? '';
    final model = vehicle['model'] as String? ?? '';
    final plate = vehicle['licensePlate'] as String? ?? '';
    final type = vehicle['type'] as String? ?? 'Car';
    final driverName = vehicle['driverName'] as String?;
    final status = vehicle['status'] as String? ?? 'Offline';
    final alertness = vehicle['alertness'] as int? ?? 0;
    final assignedDriverId = vehicle['assignedDriverId'] as String?;
    final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;
    final ownerEmail = vehicle['ownerEmail'] as String? ?? '';

    final typeIcons = {
      'Car': Icons.directions_car,
      'Bus': Icons.directions_bus,
      'Van': Icons.airport_shuttle,
      'Truck': Icons.local_shipping,
      'Rickshaw': Icons.electric_rickshaw,
    };

    Color statusColor;
    if (hasDriver) {
      statusColor = const Color(0xFF4CAF50);
    } else if (status.toLowerCase() == 'critical') {
      statusColor = Colors.red;
    } else {
      statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: statusColor.withOpacity(0.15),
                child: Icon(typeIcons[type] ?? Icons.directions_car, size: 20, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$make $model'.trim().isNotEmpty ? '$make $model'.trim() : 'Unknown Vehicle',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text(plate, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasDriver ? 'Active' : status,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF607D8B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(type, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Icon(Icons.person, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  hasDriver ? (driverName ?? 'Assigned') : 'Unassigned',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              if (alertness > 0) ...[
                Icon(
                  Icons.speed,
                  size: 14,
                  color: alertness >= 70 ? const Color(0xFF4CAF50) : alertness >= 50 ? const Color(0xFFFF9800) : Colors.red,
                ),
                const SizedBox(width: 4),
                Text('$alertness%', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ],
          ),
          if (ownerEmail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.email_outlined, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(ownerEmail, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => _showEditVehicleDialog(vehicle),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 15, color: Color(0xFF2196F3)),
                      SizedBox(width: 4),
                      Text('Edit', style: TextStyle(fontSize: 12, color: Color(0xFF2196F3), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _confirmDeleteVehicle(vehicle),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, size: 15, color: Colors.red),
                      SizedBox(width: 4),
                      Text('Delete', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTypeBadge(String type) {
    final typeColors = {
      'Car': const Color(0xFF2196F3),
      'Bus': const Color(0xFF9C27B0),
      'Van': const Color(0xFFFF9800),
      'Truck': const Color(0xFF607D8B),
      'Rickshaw': const Color(0xFF4CAF50),
    };
    final color = typeColors[type] ?? Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          type,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildVehicleStatusBadge(String status, bool hasDriver) {
    Color color;
    String displayStatus;
    if (hasDriver) {
      color = const Color(0xFF4CAF50);
      displayStatus = 'Active';
    } else if (status.toLowerCase() == 'critical') {
      color = Colors.red;
      displayStatus = 'Critical';
    } else {
      color = Colors.grey[500]!;
      displayStatus = status;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          displayStatus,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildAlertnessBadge(int alertness) {
    Color color;
    if (alertness >= 70) {
      color = const Color(0xFF4CAF50);
    } else if (alertness >= 50) {
      color = const Color(0xFFFF9800);
    } else if (alertness > 0) {
      color = Colors.red;
    } else {
      color = Colors.grey[400]!;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            alertness > 0 ? '$alertness%' : 'N/A',
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleActionsCell(Map<String, dynamic> vehicle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2196F3)),
            tooltip: 'Edit vehicle',
            onPressed: () => _showEditVehicleDialog(vehicle),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete vehicle',
            onPressed: () => _confirmDeleteVehicle(vehicle),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditVehicleDialog(Map<String, dynamic> vehicle) async {
    final docId = vehicle['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot edit: Vehicle ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final formKey = GlobalKey<FormState>();
    final makeCtrl = TextEditingController(text: vehicle['make'] as String? ?? '');
    final modelCtrl = TextEditingController(text: vehicle['model'] as String? ?? '');
    final yearCtrl = TextEditingController(text: vehicle['year'] as String? ?? '');
    final plateCtrl = TextEditingController(text: vehicle['licensePlate'] as String? ?? '');
    String selectedType = vehicle['type'] as String? ?? 'Car';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Color(0xFF2196F3), size: 22),
                SizedBox(width: 8),
                Text('Edit Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: makeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Make',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Make is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: modelCtrl,
                      decoration: InputDecoration(
                        labelText: 'Model',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Model is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: yearCtrl,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Year is required';
                        final year = int.tryParse(v.trim());
                        if (year == null || year < 1900 || year > DateTime.now().year + 1) {
                          return 'Enter a valid year';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: plateCtrl,
                      decoration: InputDecoration(
                        labelText: 'License Plate',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'License plate is required' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: ['Car', 'Bus', 'Van', 'Truck', 'Rickshaw']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedType = val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;

                  // Check for duplicate license plate
                  final plateQuery = await _firestore.collection('vehicles')
                      .where('licensePlate', isEqualTo: plateCtrl.text.trim())
                      .get();
                  final hasDuplicate = plateQuery.docs.any((d) => d.id != docId);
                  if (hasDuplicate) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('A vehicle with this license plate already exists'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }

                  Navigator.pop(ctx);
                  try {
                    await _firestore.collection('vehicles').doc(docId).update({
                      'make': makeCtrl.text.trim(),
                      'model': modelCtrl.text.trim(),
                      'year': yearCtrl.text.trim(),
                      'licensePlate': plateCtrl.text.trim(),
                      'type': selectedType,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vehicle updated successfully'), backgroundColor: Color(0xFF4CAF50)),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating vehicle: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteVehicle(Map<String, dynamic> vehicle) async {
    final docId = vehicle['docId'] as String?;
    if (docId == null || docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: Vehicle ID not found'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final make = vehicle['make'] as String? ?? '';
    final model = vehicle['model'] as String? ?? '';
    final plate = vehicle['licensePlate'] as String? ?? '';
    final assignedDriverId = vehicle['assignedDriverId'] as String?;
    final hasDriver = assignedDriverId != null && assignedDriverId.isNotEmpty;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Delete Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this vehicle?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$make $model'.trim().isNotEmpty ? '$make $model' : 'Unknown Vehicle', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (plate.isNotEmpty)
                    Text('Plate: $plate', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                ],
              ),
            ),
            if (hasDriver) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Color(0xFFFF9800)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This vehicle has an assigned driver. The driver will be unassigned.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFFF9800)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection('vehicles').doc(docId).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${make.isNotEmpty ? "$make $model" : "Vehicle"} has been deleted'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting vehicle: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // =============================================
  // DOCUMENT APPROVAL (Real-time)
  // - Driver CNIC/License approval
  // - Owner vehicle book/id card approval
  // =============================================
  String _formatTime(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return '${diff.inDays} d ago';
  }

  Future<void> _approveDriverDocs(DriverDocumentSubmission s) async {
    setState(() => _processingSubmissionId = s.id);
    try {
      await _driverDocumentSubmissionService.approveSubmission(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Driver documents approved. Vehicle assignment attempted.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _rejectDriverDocs(DriverDocumentSubmission s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject driver documents'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (reason == null) return;
    setState(() => _processingSubmissionId = s.id);
    try {
      await _driverDocumentSubmissionService.rejectSubmission(s.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _approveOwnerVehicle(OwnerVehicleSubmission s) async {
    setState(() => _processingSubmissionId = s.id);
    try {
      await _ownerVehicleSubmissionService.approveSubmission(s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vehicle booking approved. Vehicle assignment attempted (if driver queue exists).'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  Future<void> _rejectOwnerVehicle(OwnerVehicleSubmission s) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Reject vehicle submission'),
          content: TextField(
            controller: c,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
          ],
        );
      },
    );
    if (reason == null) return;

    setState(() => _processingSubmissionId = s.id);
    try {
      await _ownerVehicleSubmissionService.rejectSubmission(s.id, reason: reason.isEmpty ? null : reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submission rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processingSubmissionId = null);
    }
  }

  void _showDocPreview(String url, String title) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text(title, style: const TextStyle(fontSize: 16)),
                automaticallyImplyLeading: false,
                actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
              ),
              SizedBox(
                height: 400,
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Could not load image'),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentApproval() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approvals (Real-time)',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Driver documents + Owner vehicle books (updates in real time)',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 1) Driver document approval
          StreamBuilder<List<DriverDocumentSubmission>>(
            stream: _driverDocumentSubmissionService.watchPendingSubmissions(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? [];
              final count = pending.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Driver Documents',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count Pending',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF9800),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))
                  else if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'No driver document submissions',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 600;
                        if (isMobile) {
                          return Column(
                            children: pending.map((s) => _buildMobileDriverDocCard(s)).toList(),
                          );
                        }
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(flex: 3, child: Text('Driver', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 2, child: Text('Submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 2, child: Text('Documents', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 2, child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                ],
                              ),
                            ),
                            ...pending.map((s) => _buildDriverDocRow(s)),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // 2) Owner vehicle book approval
          StreamBuilder<List<OwnerVehicleSubmission>>(
            stream: _ownerVehicleSubmissionService.watchPendingSubmissions(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? [];
              final count = pending.length;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Owner Vehicles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count Pending',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2196F3),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))
                  else if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'No owner vehicle submissions',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 600;
                        if (isMobile) {
                          return Column(
                            children: pending.map((s) => _buildMobileOwnerVehicleCard(s)).toList(),
                          );
                        }
                        return Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(flex: 2, child: Text('Owner', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 3, child: Text('Vehicle', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 2, child: Text('Submitted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                  Expanded(flex: 2, child: Text('Actions', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54))),
                                ],
                              ),
                            ),
                            ...pending.map((s) => _buildOwnerVehicleRow(s)),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDriverDocRow(DriverDocumentSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.driverName.isNotEmpty ? s.driverName[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.driverName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatTime(s.submittedAt),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton(
                  onPressed: () => _showDocPreview(s.cnicUrl, 'CNIC'),
                  child: const Text('CNIC', style: TextStyle(fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _showDocPreview(s.licenseUrl, 'License'),
                  child: const Text('License', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: busy ? null : () => _approveDriverDocs(s),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                    minimumSize: Size.zero,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Approve', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => _rejectDriverDocs(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileDriverDocCard(DriverDocumentSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.driverName.isNotEmpty ? s.driverName[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFF9800).withOpacity(0.15),
                child: Text(initial, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFFF9800))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.driverName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(_formatTime(s.submittedAt), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(onPressed: () => _showDocPreview(s.cnicUrl, 'CNIC'), child: const Text('CNIC')),
              OutlinedButton(onPressed: () => _showDocPreview(s.licenseUrl, 'License'), child: const Text('License')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _approveDriverDocs(s),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _rejectDriverDocs(s),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerVehicleRow(OwnerVehicleSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.ownerName.isNotEmpty ? s.ownerName[0].toUpperCase() : '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[100]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF2196F3).withOpacity(0.15),
                  child: Text(
                    initial,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.ownerName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              '${s.make} ${s.model} · ${s.licensePlate} (${s.type})',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatTime(s.submittedAt),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _showDocPreview(s.vehicleBookUrl, 'Vehicle book'),
                  child: const Text('View', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: busy ? null : () => _approveOwnerVehicle(s),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                    minimumSize: Size.zero,
                  ),
                  child: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: busy ? null : () => _rejectOwnerVehicle(s),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Reject', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileOwnerVehicleCard(OwnerVehicleSubmission s) {
    final busy = _processingSubmissionId == s.id;
    final initial = s.ownerName.isNotEmpty ? s.ownerName[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF2196F3).withOpacity(0.15),
                child: Text(initial, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.ownerName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text('${s.make} ${s.model} · ${s.licensePlate}', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_formatTime(s.submittedAt), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _showDocPreview(s.vehicleBookUrl, 'Vehicle book'),
                  child: const Text('View vehicle book'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _approveOwnerVehicle(s),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
                  child: busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _rejectOwnerVehicle(s),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                  child: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Removed: _buildFleetOverview, _buildGlobalFleetStatus, _buildLiveFleetMap,
}
