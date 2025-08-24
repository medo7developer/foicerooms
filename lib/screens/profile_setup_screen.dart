import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:developer';
import '../models/user_model.dart';
import '../providers/user_providers/auth_provider.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  File? _selectedImage;
  String? _selectedAvatar;
  int _selectedAvatarIndex = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // تعيين الاسم الحالي من Google
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _nameController.text = authProvider.playerName;
    log('تم تهيئة شاشة إعداد الملف الشخصي: اسم المستخدم=${authProvider
        .playerName}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                _buildProfileCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(
          Icons.person_add,
          color: Colors.white,
          size: 60,
        ),
        const SizedBox(height: 20),
        const Text(
          'إعداد ملفك الشخصي',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const Text(
          'اختر صورتك واسمك للعبة',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // اختيار الصورة
          _buildImageSelection(),
          const SizedBox(height: 30),

          // اختيار الاسم
          _buildNameInput(),
          const SizedBox(height: 30),

          // أزرار الحفظ والتخطي
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildImageSelection() {
    return Column(
      children: [
        const Text(
          'اختر صورتك الشخصية',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),

        // عرض الصورة المختارة
        _buildSelectedImage(),
        const SizedBox(height: 20),

        // خيارات الصورة
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildImageOption(
              icon: Icons.photo_library,
              label: 'من المعرض',
              onTap: _pickImageFromGallery,
            ),
            _buildImageOption(
              icon: Icons.camera_alt,
              label: 'من الكاميرا',
              onTap: _pickImageFromCamera,
            ),
            _buildImageOption(
              icon: Icons.face,
              label: 'أفاتار',
              onTap: _showAvatarSelection,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedImage() {
    final authProvider = Provider.of<AuthProvider>(context);

    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 3),
      ),
      child: ClipOval(
        child: _selectedImage != null
            ? Image.file(_selectedImage!, fit: BoxFit.cover)
            : _selectedAvatar != null
            ? Image.asset(_selectedAvatar!, fit: BoxFit.cover)
            : authProvider.playerImageUrl != null
            ? Image.network(authProvider.playerImageUrl!, fit: BoxFit.cover)
            : Container(
          color: Colors.grey.shade200,
          child: Icon(
            Icons.person,
            size: 60,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildImageOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.purple),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اسمك في اللعبة',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'أدخل اسمك',
            prefixIcon: const Icon(Icons.person),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
              'حفظ والمتابعة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _isLoading ? null : _skipSetup,
          child: const Text(
            'تخطي الآن',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  // اختيار صورة من المعرض
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedAvatar = null;
        });
        log('تم اختيار صورة من المعرض');
      }
    } catch (e) {
      log('خطأ في اختيار الصورة: $e');
      _showErrorSnackBar('خطأ في اختيار الصورة');
    }
  }

  // اختيار صورة من الكاميرا
  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 500,
        maxHeight: 500,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedAvatar = null;
        });
        log('تم التقاط صورة من الكاميرا');
      }
    } catch (e) {
      log('خطأ في التقاط الصورة: $e');
      _showErrorSnackBar('خطأ في التقاط الصورة');
    }
  }

  // عرض اختيار الأفاتار
  void _showAvatarSelection() {
    showModalBottomSheet(
      context: context,
      builder: (context) =>
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'اختر أفاتار',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 120,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: AvatarAssets.defaultAvatars.length,
                    itemBuilder: (context, index) {
                      final avatar = AvatarAssets.defaultAvatars[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatar = avatar;
                            _selectedAvatarIndex = index;
                            _selectedImage = null;
                          });
                          log('تم اختيار أفاتار: $avatar');
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedAvatarIndex == index
                                  ? Colors.purple
                                  : Colors.grey.shade300,
                              width: 3,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              avatar,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade300,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.grey.shade600,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  // حفظ الملف الشخصي
  Future<void> _saveProfile() async {
    if (_nameController.text
        .trim()
        .isEmpty) {
      _showErrorSnackBar('يرجى إدخال اسم');
      return;
    }

    setState(() => _isLoading = true);

    try {
      log('بدء حفظ الملف الشخصي: ${_nameController.text.trim()}');

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final success = await authProvider.updateUserProfile(
        displayName: _nameController.text.trim(),
        customAvatarPath: _selectedAvatar,
        avatarFile: _selectedImage,
      );

      if (success) {
        log('تم حفظ الملف الشخصي بنجاح');

        // انتظار قصير للتأكد من تحديث البيانات
        await Future.delayed(const Duration(milliseconds: 300));

        // التحقق من حالة الملف الشخصي مرة أخرى
        await authProvider.refreshUser();

        log('حالة الملف الشخصي بعد الحفظ: ${authProvider.isProfileComplete}');

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        _showErrorSnackBar('فشل في حفظ الملف الشخصي');
        log('فشل في حفظ الملف الشخصي');
      }
    } catch (e) {
      log('خطأ في حفظ البيانات: $e');
      _showErrorSnackBar('خطأ في حفظ البيانات');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // تخطي إعداد الملف - مع تحديث الحالة
  Future<void> _skipSetup() async {
    log('تم تخطي إعداد الملف الشخصي');

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // حفظ اسم افتراضي على الأقل إذا كان فارغاً
      String displayName = _nameController.text.trim();
      if (displayName.isEmpty) {
        displayName = authProvider.playerName.isNotEmpty
            ? authProvider.playerName
            : 'لاعب ${DateTime
            .now()
            .millisecondsSinceEpoch
            .toString()
            .substring(8)}';
      }

      // تحديث مع الاسم على الأقل
      await authProvider.updateUserProfile(displayName: displayName);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      log('خطأ في تخطي الإعداد: $e');
      // في حالة الخطأ، انتقل للصفحة الرئيسية مباشرة
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}