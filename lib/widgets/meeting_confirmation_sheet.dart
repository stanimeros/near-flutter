import 'package:flutter/material.dart';
import 'package:action_slider/action_slider.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class MeetingConfirmationSheet extends StatefulWidget {
  final Point point;
  final Meeting? currentMeeting;
  final String currentUserId;
  final VoidCallback? onReject;
  final VoidCallback? onAccept;
  final Function(DateTime)? onConfirm;
  final bool viewOnly;

  const MeetingConfirmationSheet({
    super.key,
    required this.point,
    this.currentMeeting,
    required this.currentUserId,
    this.onReject,
    this.onAccept,
    this.onConfirm,
    this.viewOnly = false,
  });

  @override
  State<MeetingConfirmationSheet> createState() => _MeetingConfirmationSheetState();
}

class _MeetingConfirmationSheetState extends State<MeetingConfirmationSheet> {
  DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    // Initialize with current meeting datetime if updating an existing meeting
    if (widget.currentMeeting != null) {
      selectedDateTime = widget.currentMeeting!.datetime;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If we have a current meeting and we're not creating/updating
    if (widget.currentMeeting != null && widget.viewOnly) {
      final bool canInteract = widget.currentMeeting!.status == MeetingStatus.suggested;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withAlpha(50),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.mapPin,
                  color: widget.currentMeeting!.status.color,
                ),
                const SizedBox(width: 8),
                Text(
                  'Meeting ${widget.currentMeeting!.status.displayName}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatDateTime(widget.currentMeeting!.datetime),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.currentMeeting!.status.color.withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.currentMeeting!.status.displayName,
                    style: TextStyle(
                      color: widget.currentMeeting!.status.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Created on: ${formatDateTime(widget.currentMeeting!.createdAt)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (canInteract)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.onReject != null)
                    ElevatedButton.icon(
                      onPressed: () async {
                        widget.onReject!();
                        // Add a small delay before closing the sheet
                        await Future.delayed(const Duration(milliseconds: 500));
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(LucideIcons.x, color: Colors.red),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    ),
                  if (widget.onAccept != null)
                    ElevatedButton.icon(
                      onPressed: () async {
                        widget.onAccept!();
                        // Add a small delay before closing the sheet
                        await Future.delayed(const Duration(milliseconds: 500));
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(LucideIcons.check, color: Colors.green),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    }

    // For creating a new meeting or updating an existing one
    final bool isUpdating = widget.currentMeeting != null;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
              color: Theme.of(context).colorScheme.outline.withAlpha(50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            isUpdating ? 'Update meeting location?' : 'Create meeting here?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          Text(
            formatDateTime(selectedDateTime),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _showDateTimePicker(context),
            child: const Text('Change Date & Time'),
          ),
          const SizedBox(height: 24),
          ActionSlider.standard(
            width: MediaQuery.of(context).size.width - 48,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            toggleColor: Theme.of(context).colorScheme.primary,
            icon: const Icon(LucideIcons.arrowRight, color: Colors.white),
            successIcon: const Icon(LucideIcons.check, color: Colors.white),
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
              
              // Call onConfirm first and wait for it to complete
              if (context.mounted && widget.onConfirm != null) {
                widget.onConfirm!(selectedDateTime);
              }
              
              // Show success state and then close the sheet
              await Future.delayed(const Duration(milliseconds: 500));
              controller.success();
              await Future.delayed(const Duration(milliseconds: 500));
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(isUpdating ? 'Slide to update location' : 'Slide to create'),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateTimePicker(BuildContext context) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (date != null && context.mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      );
    
      if (time != null) {
        setState(() {
          selectedDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }
} 