import 'package:flutter/material.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:action_slider/action_slider.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MeetingConfirmationSheet extends StatelessWidget {
  final jts.Point point;
  final VoidCallback onConfirm;

  const MeetingConfirmationSheet({
    super.key,
    required this.point,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withAlpha(100),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Suggest Meeting Here?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          ActionSlider.standard(
            width: MediaQuery.of(context).size.width - 48, // Full width minus padding
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            toggleColor: Theme.of(context).colorScheme.primary,
            icon: const Icon(
              LucideIcons.arrowRight,
              color: Colors.white,
            ),
            successIcon: const Icon(
              LucideIcons.check,
              color: Colors.white,
            ),
            loadingIcon: const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: Colors.white,
              ),
            ),
            action: (controller) async {
              controller.loading();
              await Future.delayed(const Duration(milliseconds: 500));
              controller.success();
              await Future.delayed(const Duration(milliseconds: 500));
              if (context.mounted) {
                Navigator.pop(context);
                onConfirm();
              }
            },
            child: const Text('Slide to confirm'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
} 