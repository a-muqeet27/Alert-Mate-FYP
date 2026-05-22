import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AlertMateBrandingSize { splash, auth }

/// Shared logo + app name header for splash and auth screens.
class AlertMateBranding extends StatelessWidget {
  const AlertMateBranding({
    super.key,
    this.size = AlertMateBrandingSize.auth,
  });

  final AlertMateBrandingSize size;

  static const String _logoAsset = 'assets/images/Alert Mate New.png';

  @override
  Widget build(BuildContext context) {
    if (size == AlertMateBrandingSize.auth) {
      return _buildAuthHorizontal();
    }
    return _buildSplashVertical();
  }

  Widget _buildAuthHorizontal() {
    const titleSize = 24.0;
    const taglineSize = 12.0;
    const logoW = 92.0;
    const logoH = 70.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTitle(titleSize, TextAlign.left),
                const SizedBox(height: 4),
                _buildTagline(taglineSize, TextAlign.left),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildLogo(logoW, logoH),
        ],
      ),
    );
  }

  Widget _buildSplashVertical() {
    const logoImageW = 200.0;
    const logoImageH = 155.0;
    const titleSize = 34.0;
    const taglineSize = 15.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogo(logoImageW, logoImageH),
        const SizedBox(height: 20),
        _buildTitle(titleSize, TextAlign.center),
        const SizedBox(height: 10),
        _buildTagline(taglineSize, TextAlign.center),
      ],
    );
  }

  Widget _buildLogo(double width, double height) {
    return Image.asset(
      _logoAsset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.shield_outlined,
        size: width * 0.65,
        color: AppColors.azure,
      ),
    );
  }

  Widget _buildTitle(double fontSize, TextAlign align) {
    return Text(
      'ALERT MATE',
      textAlign: align,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: align == TextAlign.left ? 2.0 : 3.5,
        height: 1.1,
        color: AppColors.azure,
      ),
    );
  }

  Widget _buildTagline(double fontSize, TextAlign align) {
    return Text(
      'Drowsiness Detection',
      textAlign: align,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: AppColors.lightGray,
        letterSpacing: 0.6,
      ),
    );
  }
}
