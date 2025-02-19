import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/pick_profile_picture.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:flutter_near/services/user_provider.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  XFile? newProfilePicture;
  final ImagePicker picker = ImagePicker();

  bool isLoading = false;
  bool uInvalid = false;
  FocusNode uFocusNode = FocusNode();
  TextEditingController uController = TextEditingController();
  TextEditingController eController = TextEditingController();
  double kValue = 2; // Default k-anonymity value

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    final nearUser = userProvider.nearUser;
    
    uController = TextEditingController(text: nearUser?.username);
    eController = TextEditingController(text: nearUser?.email);
    kValue = (nearUser?.kAnonymity ?? 2).toDouble();
  }

  Future<void> saveChanges() async {
    final userProvider = context.read<UserProvider>();
    final nearUser = userProvider.nearUser;
    if (nearUser == null) return;

    String newUsername = uController.text
      .trim().toLowerCase().replaceAll(' ', '');

    if (!uInvalid) {
      setState(() {
        isLoading = true;
      });

      try {
        // Update user data in Firestore
        await FirestoreService().setUser(nearUser.uid, newUsername, kValue.round().toString());

        // Update profile picture if changed
        if (newProfilePicture != null) {
          await FirestoreService().setProfilePicture(nearUser.uid, newProfilePicture!.path);
        }

        // Get updated user data
        final updatedUser = await FirestoreService().getUser(nearUser.uid);
        if (updatedUser != null) {
          // Update the provider without notifying listeners
          userProvider.updateUserSilently(updatedUser);
        }

        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error saving changes: $e');
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
      }
    }
  }

  String? uError(String value) {
    if (value.length < 4) {
      return "Username should contain at least 4 characters";
    } else if (value.length > 10) {
      return "Username should not contain more than 10 characters";
    }
    return null;
  }

  Future<XFile?> pickImage() async {
    final XFile? selectedImage = await picker.pickImage(
      source: ImageSource.gallery,
      maxHeight: 512,
      maxWidth: 512,
    );
    
    setState(() {
      newProfilePicture = selectedImage;
    });

    return newProfilePicture;
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    
    if (userProvider.isLoading) {
      return const CustomLoader();
    }

    final nearUser = userProvider.nearUser;
    if (nearUser == null) {
      return const Text('No user data');
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              PickProfilePicture(
                user: nearUser,
                pickImage: pickImage,
                size: 55,
                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
              ),
              const SizedBox(width: 12),
              Text(
                nearUser.username,
                style: const TextStyle(
                  fontSize: 20
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(
                  size: 18,
                  LucideIcons.logOut
                ),
              )
            ]
          ),
          const SizedBox(height: 20),
          TextField(
            focusNode: uFocusNode,
            controller: uController,
            onEditingComplete: () {
              setState(() {
                uInvalid = uError(uController.text) != null;
              });
              uFocusNode.unfocus();
            },
            onTapOutside: (event) {
              setState(() {
                uInvalid = uError(uController.text) != null;
              });
              uFocusNode.unfocus();
            },
            decoration: InputDecoration(
              labelText: 'Username',
              errorText: uInvalid ? uError(uController.text) : null,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            readOnly: true,
            enableInteractiveSelection: false,
            controller: eController,
            decoration: const InputDecoration(
              labelText: 'Email',
            ),
          ),
          const SizedBox(height: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'k-Anonymity: ${kValue.round()}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Adjust the level of anonymity for your data.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Slider(
                value: kValue,
                min: 2,
                max: 20,
                divisions: 18,
                padding: EdgeInsets.symmetric(vertical: 12),
                label: kValue.round().toString(),
                onChanged: (value) {
                  setState(() {
                    kValue = value;
                  });
                },
              ),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: isLoading ? null : () => saveChanges(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Save changes'),
                SizedBox(width: 8),
                if (isLoading) Icon(LucideIcons.loader, size: 18).animate().rotate(duration: 1.seconds, curve: Curves.linear),
                if (!isLoading) Icon(LucideIcons.save, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}