import 'package:flutter/material.dart';
import 'package:action_slider/action_slider.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MeetingConfirmationSheet extends StatefulWidget {
  final Point point;
  final Meeting? currentMeeting;
  final String currentUserId;
  final bool isNewSuggestion;
  final bool isCounterProposal;
  final VoidCallback? onCancel;
  final VoidCallback? onReject;
  final VoidCallback? onAccept;
  final Function(DateTime)? onConfirm;

  const MeetingConfirmationSheet({
    super.key,
    required this.point,
    this.currentMeeting,
    required this.currentUserId,
    required this.isNewSuggestion,
    this.isCounterProposal = false,
    this.onCancel,
    this.onReject,
    this.onAccept,
    this.onConfirm,
  });

  @override
  State<MeetingConfirmationSheet> createState() => _MeetingConfirmationSheetState();
}

class _MeetingConfirmationSheetState extends State<MeetingConfirmationSheet> {
  DateTime selectedDateTime = DateTime.now().add(const Duration(days: 1));

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  bool _isMeetingPast(DateTime time) {
    return time.isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNewSuggestion && widget.currentMeeting != null) {
      final bool isPast = _isMeetingPast(widget.currentMeeting!.time);
      final bool canInteract = (widget.currentMeeting!.status == MeetingStatus.pending || 
                              widget.currentMeeting!.status == MeetingStatus.counterProposal) && 
                              !isPast;

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
                color: Theme.of(context).colorScheme.outline.withAlpha(100),
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
            Text(
              _formatDateTime(widget.currentMeeting!.time),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (isPast)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Meeting time has passed',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            if (canInteract)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (widget.currentUserId == widget.currentMeeting!.senderId)
                    ElevatedButton.icon(
                      onPressed: widget.onCancel,
                      icon: const Icon(LucideIcons.x, color: Colors.red),
                      label: const Text('Cancel'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.onReject != null)
                          ElevatedButton.icon(
                            onPressed: widget.onReject,
                            icon: const Icon(LucideIcons.x, color: Colors.red),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
                        if (widget.onReject != null && widget.onAccept != null)
                          const SizedBox(width: 16),
                        if (widget.onAccept != null)
                          ElevatedButton.icon(
                            onPressed: widget.onAccept,
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
          ],
        ),
      );
    }

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
              color: Theme.of(context).colorScheme.outline.withAlpha(100),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            widget.isCounterProposal ? 'Counter-proposal?' : 'Create meeting here?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(LucideIcons.calendar),
            title: Text(
              'Meeting time: ${_formatDateTime(selectedDateTime)}',
            ),
            onTap: () => _showDateTimePicker(context),
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
              await Future.delayed(const Duration(milliseconds: 500));
              controller.success();
              await Future.delayed(const Duration(milliseconds: 500));
              if (context.mounted) {
                Navigator.pop(context);
                widget.onConfirm!(selectedDateTime);
              }
            },
            child: Text(widget.isCounterProposal ? 'Slide to counter-propose' : 'Slide to create'),
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