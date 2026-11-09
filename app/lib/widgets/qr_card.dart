import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../design/tokens.dart';

/// A code for another device's camera, on the white card the design kit
/// draws for it.
class QrCard extends StatelessWidget {
  const QrCard({
    super.key,
    required this.data,
    required this.label,
    this.size = 220,
  });

  /// What the code says.
  final String data;

  /// What it is, for a screen reader.
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ExcludeSemantics(
          child: QrImageView(
            data: data,
            // The least error correction keeps the squares as big as they
            // can be, which is what a camera needs from a long code.
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.white,
          ),
        ),
      ),
    );
  }
}
