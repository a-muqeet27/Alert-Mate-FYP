import 'package:flutter/material.dart';

/// Hamburger button that opens the [Scaffold] drawer, with an optional unread count.
class MobileDrawerMenuButton extends StatelessWidget {
  const MobileDrawerMenuButton({
    super.key,
    this.unreadBadgeStream,
    this.iconColor = Colors.black87,
  });

  final Stream<int>? unreadBadgeStream;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    void openDrawer() {
      Scaffold.of(context).openDrawer();
    }

    if (unreadBadgeStream == null) {
      return IconButton(
        icon: Icon(Icons.menu, color: iconColor),
        onPressed: openDrawer,
      );
    }

    return StreamBuilder<int>(
      stream: unreadBadgeStream,
      initialData: 0,
      builder: (context, snapshot) {
        final n = snapshot.data ?? 0;
        return IconButton(
          onPressed: openDrawer,
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(
              n > 99 ? '99+' : '$n',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            child: Icon(Icons.menu, color: iconColor),
          ),
        );
      },
    );
  }
}
