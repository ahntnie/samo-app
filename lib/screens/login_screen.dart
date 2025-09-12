import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool showPassword = false;
  bool rememberPassword = false;
  String? errorText;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  // Kiểm tra session hiện tại và tự động đăng nhập nếu có thể
  Future<void> _checkExistingSession() async {
    setState(() {
      isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('login_email');
      final savedPassword = prefs.getString('login_password');
      final savedRememberPassword = prefs.getBool('login_rememberPassword') ?? false;

      if (savedEmail != null && savedPassword != null && savedRememberPassword) {
        // Thử đăng nhập với thông tin đã lưu
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: savedEmail,
          password: savedPassword,
        );

        if (response.user != null) {
          // Lấy thông tin tenant từ dự án chính
          final tenantData = await Supabase.instance.client
              .from('tenants')
              .select('supabase_url, supabase_anon_key')
              .eq('user_id', response.user!.id)
              .maybeSingle();

          if (tenantData != null) {
            final url = tenantData['supabase_url'];
            final anonKey = tenantData['supabase_anon_key'];

            // Tạo Supabase client cho dự án phụ
            final tenantClient = SupabaseClient(url, anonKey);

            // Lưu thông tin tenant
            await _saveTenantData(url, anonKey);
            
            if (mounted) {
              goToHome(tenantClient);
              return;
            }
          }
        }
      }

      // Load saved credentials for manual login if auto-login fails
      if (savedEmail != null && savedPassword != null && savedRememberPassword) {
        setState(() {
          emailController.text = savedEmail;
          passwordController.text = savedPassword;
          rememberPassword = true;
        });
      }
    } catch (e) {
      print('Auto-login error: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Đăng xuất phiên hiện tại và xóa thông tin tenant
  Future<void> _clearSessionAndCredentials() async {
    await Supabase.instance.client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tenant_url');
    await prefs.remove('tenant_anon_key');
    if (!rememberPassword) {
      await prefs.remove('login_email');
      await prefs.remove('login_password');
      await prefs.setBool('login_rememberPassword', false);
    }
  }

  // Lưu thông tin đăng nhập
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberPassword) {
      await prefs.setString('login_email', emailController.text.trim());
      await prefs.setString('login_password', passwordController.text.trim());
      await prefs.setBool('login_rememberPassword', true);
    } else {
      await prefs.remove('login_email');
      await prefs.remove('login_password');
      await prefs.setBool('login_rememberPassword', false);
    }
  }

  // Lưu thông tin tenant vào SharedPreferences
  Future<void> _saveTenantData(String url, String anonKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tenant_url', url);
    await prefs.setString('tenant_anon_key', anonKey);
  }

  // Đăng nhập
  Future<void> signIn() async {
    print('Initializing signIn...');
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorText = null;
    });

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (response.user != null) {
        // Lấy thông tin tenant từ dự án chính dựa trên user_id
        final tenantData = await Supabase.instance.client
            .from('tenants')
            .select('supabase_url, supabase_anon_key')
            .eq('user_id', response.user!.id)
            .maybeSingle();

        if (tenantData != null) {
          final url = tenantData['supabase_url'];
          final anonKey = tenantData['supabase_anon_key'];

          // Tạo Supabase client cho dự án phụ
          final tenantClient = SupabaseClient(url, anonKey);

          // Lưu thông tin tenant và credentials
          await _saveTenantData(url, anonKey);
          await _saveCredentials();
          
          if (mounted) {
            goToHome(tenantClient);
          }
        } else {
          setState(() {
            errorText = 'Không tìm thấy dự án phụ cho người dùng này';
          });
        }
      } else {
        setState(() {
          errorText = 'Sai email hoặc mật khẩu';
        });
      }
    } catch (e) {
      setState(() {
        errorText = 'Lỗi đăng nhập: $e';
      });
      print('Login error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  // Đặt lại mật khẩu
  Future<void> resetPassword(String email) async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorText = null;
    });

    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'io.supabase.flutterquickstart://reset-callback/',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email đặt lại mật khẩu đã được gửi! Vui lòng kiểm tra hộp thư.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorText = 'Lỗi khi gửi email đặt lại mật khẩu: $e';
      });
      print('Reset password error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  // Chuyển đến màn hình Home, truyền SupabaseClient của dự án phụ
  void goToHome(SupabaseClient tenantClient) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(tenantClient: tenantClient),
        ),
      );
    });
  }

  // Hiển thị dialog đặt lại mật khẩu
  void showResetPasswordDialog() {
    final resetEmailController = TextEditingController();
    String? resetError;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lấy lại mật khẩu'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: resetEmailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: resetError,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = resetEmailController.text.trim();

              if (email.isEmpty) {
                setState(() {
                  resetError = 'Vui lòng nhập email';
                });
                return;
              }

              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
                setState(() {
                  resetError = 'Email không hợp lệ';
                });
                return;
              }

              Navigator.pop(context);
              await resetPassword(email);
            },
            child: const Text('Gửi email'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121826),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Đăng nhập',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chào mừng bạn quay lại!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: emailController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: !showPassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Mật khẩu',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: showPassword,
                            onChanged: (value) => setState(() => showPassword = value!),
                            activeColor: Colors.blue,
                          ),
                          const Text('Hiện mật khẩu', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                      Row(
                        children: [
                          Checkbox(
                            value: rememberPassword,
                            onChanged: (value) => setState(() => rememberPassword = value!),
                            activeColor: Colors.blue,
                          ),
                          const Text('Nhớ mật khẩu', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: isLoading ? null : signIn,
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Đăng nhập', style: TextStyle(fontSize: 16, color: Colors.white)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // TextButton(
                      //   onPressed: isLoading
                      //       ? null
                      //       : () {
                      //           Navigator.push(
                      //             context,
                      //             MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      //           );
                      //         },
                      //   child: const Text(
                      //     'Đăng ký',
                      //     style: TextStyle(color: Colors.white, fontSize: 16),
                      //   ),
                      // ),
                      TextButton(
                        onPressed: isLoading ? null : showResetPasswordDialog,
                        child: const Text(
                          'Lấy lại mật khẩu',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(errorText!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: const Text(
              'Phần Mềm Viết Bởi Vũ Ngọc Tú\n0948233333',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
}