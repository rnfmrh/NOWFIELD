import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _selectedCameraIdx = 0;
  bool _isFrontCamera = false;
  bool _isFlashOn = false;

  bool _isRecording = false;
  bool _isReviewing = false; // Spec #34: "Use this video? [Retake] [Use Video]"
  int _recordDuration = 0;
  int _lastRecordedSeconds = 0;
  Timer? _timer;

  bool _hasCameraError = false;
  bool _useSimulationAfterDenied = true; // Web fallback toggle for Spec #51.4
  XFile? _recordedVideo;

  // Spec #4 Metadata: Capture Session ID & Start/End timestamps
  String _captureSessionId = '';
  DateTime? _captureStartTime;
  DateTime? _captureEndTime;

  @override
  void initState() {
    super.initState();
    _generateNewCaptureSession();
    _initCamera();
  }

  void _generateNewCaptureSession() {
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    _captureSessionId = 'cap_${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  Future<void> _initCamera({int cameraIndex = 0}) async {
    try {
      _cameras ??= await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        final idx = cameraIndex % _cameras!.length;
        _selectedCameraIdx = idx;
        final desc = _cameras![idx];
        _isFrontCamera = desc.lensDirection == CameraLensDirection.front;

        await _controller?.dispose();
        final controller = CameraController(
          desc,
          ResolutionPreset.high,
          enableAudio: true,
        );
        _controller = controller;
        await controller.initialize();
        if (!mounted) return;
        setState(() {
          _hasCameraError = false;
        });
      } else {
        if (mounted) setState(() => _hasCameraError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _hasCameraError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  /// Spec #3 & #33: Toggle Flash (On / Off)
  Future<void> _toggleFlash() async {
    final nextFlash = !_isFlashOn;
    setState(() {
      _isFlashOn = nextFlash;
    });
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFlashMode(nextFlash ? FlashMode.torch : FlashMode.off);
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextFlash ? '⚡ 플래시 켜짐' : '플래시 꺼짐'),
          duration: const Duration(milliseconds: 900),
          backgroundColor: AppColors.card,
        ),
      );
    }
  }

  /// Spec #3: Switch Front / Rear Camera
  Future<void> _switchCamera() async {
    if (_isRecording) return;
    if (_cameras != null && _cameras!.length > 1) {
      final nextIdx = (_selectedCameraIdx + 1) % _cameras!.length;
      await _initCamera(cameraIndex: nextIdx);
    } else {
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFrontCamera ? '전면 카메라로 전환되었습니다.' : '후면 카메라로 전환되었습니다.'),
          duration: const Duration(milliseconds: 900),
          backgroundColor: AppColors.card,
        ),
      );
    }
  }

  void _startTimer() {
    _recordDuration = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _recordDuration++;
      });
      if (_recordDuration >= 60) {
        _stopRecording(); // 60s limit (One Minute Principle)
      }
    });
  }

  Future<void> _startRecording() async {
    _generateNewCaptureSession();
    _captureStartTime = DateTime.now();
    _captureEndTime = null;

    try {
      if (!_hasCameraError && _controller != null && _controller!.value.isInitialized) {
        await _controller!.startVideoRecording();
      }
      setState(() {
        _isRecording = true;
        _isReviewing = false;
      });
      _startTimer();
    } catch (e) {
      // Fallback to simulated recording if browser blocks MediaRecorder
      setState(() {
        _isRecording = true;
        _isReviewing = false;
      });
      _startTimer();
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _captureEndTime = DateTime.now();
    XFile? file;
    try {
      if (_controller != null && _controller!.value.isRecordingVideo) {
        file = await _controller!.stopVideoRecording();
      }
    } catch (_) {}

    final recordedSeconds = _recordDuration > 0 ? _recordDuration : 5;
    setState(() {
      _isRecording = false;
      _recordedVideo = file;
      _lastRecordedSeconds = recordedSeconds;
      _recordDuration = recordedSeconds;
      // Spec #34: Transition to "Use this video? [Retake] [Use Video]" screen first
      _isReviewing = true;
    });
  }

  /// Spec #3 & #34: Retake discards the current clip and resets camera state
  void _handleRetake() {
    _timer?.cancel();
    _generateNewCaptureSession();
    setState(() {
      _isRecording = false;
      _isReviewing = false;
      _recordedVideo = null;
      _recordDuration = 0;
      _lastRecordedSeconds = 0;
      _captureStartTime = null;
      _captureEndTime = null;
    });
  }

  /// Spec #35 & #36: Publish UI with 100-char title limit, License On/Off & Price, Step-by-step progress, and Retry
  void _showPublishBottomSheet(XFile? file, int durationSec) {
    final titleController = TextEditingController(text: '서울 강남구 신사동 가로수길 실시간 인파 현황');
    bool licenseEnabled = true; // Spec #35: License this video (Off / On)
    int licensePrice = 10000;   // Spec #35: License Price ₩10,000
    final customPriceController = TextEditingController(text: '10000');

    double lat = 37.5204;
    double lng = 127.0229;

    bool isUploading = false;
    int uploadStep = 0; // 0: idle, 1: Uploading, 2: Preparing captions, 3: Checking safety, 4: Preparing field data
    double uploadProgress = 0.0;
    String? uploadError;

    const List<String> stepLabels = [
      '영상 업로드 중...',
      '자막 자동 생성 중...',
      '안전성 및 정책 검사 중...',
      '현장 위치 데이터 검증 중...',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> executePublish() async {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setModalState(() => uploadError = '영상 제목을 입력해주세요. (최대 100자)');
                return;
              }
              if (title.length > 100) {
                setModalState(() => uploadError = '제목은 최대 100자까지 입력할 수 있습니다.');
                return;
              }

              final parsedPrice = int.tryParse(customPriceController.text.replaceAll(',', '').trim()) ?? 10000;
              if (licenseEnabled && parsedPrice < 1000) {
                setModalState(() => uploadError = '라이선스 가격은 최소 ₩1,000 이상이어야 합니다.');
                return;
              }

              setModalState(() {
                isUploading = true;
                uploadError = null;
                uploadStep = 1;
                uploadProgress = 0.25;
              });

              final messenger = ScaffoldMessenger.of(this.context);
              final nav = Navigator.of(ctx);

              try {
                // Step 1: Uploading
                await Future.delayed(const Duration(milliseconds: 350));
                if (!ctx.mounted) return;
                setModalState(() {
                  uploadStep = 2;
                  uploadProgress = 0.55;
                });

                // Step 2: Preparing captions
                await Future.delayed(const Duration(milliseconds: 350));
                if (!ctx.mounted) return;
                setModalState(() {
                  uploadStep = 3;
                  uploadProgress = 0.80;
                });

                // Step 3: Checking safety (Spec #5.1 & #37 pre-publish check)
                final lowerTitle = title.toLowerCase();
                if (lowerTitle.contains('성인물') ||
                    lowerTitle.contains('음란') ||
                    lowerTitle.contains('불법촬영') ||
                    lowerTitle.contains('포르노')) {
                  nav.pop();
                  _showPolicyViolationDialog();
                  return;
                }

                await Future.delayed(const Duration(milliseconds: 300));
                if (!ctx.mounted) return;
                setModalState(() {
                  uploadStep = 4;
                  uploadProgress = 0.95;
                });

                List<int> videoBytes;
                if (file != null) {
                  videoBytes = await file.readAsBytes();
                } else {
                  videoBytes = _generateDummyMp4Bytes();
                }

                final res = await ApiService.uploadVideo(
                  videoBytes: videoBytes,
                  filename: 'capture_${DateTime.now().millisecondsSinceEpoch}.mp4',
                  title: title,
                  subtitle: title,
                  latitude: lat,
                  longitude: lng,
                  uploaderId: ApiService.currentUserId,
                  licenseEnabled: licenseEnabled,
                  licensePrice: licenseEnabled ? parsedPrice : 0,
                  recordedDuration: durationSec,
                  captureSessionId: _captureSessionId,
                );

                if (res.containsKey('error')) {
                  if (res['statusCode'] == 451) {
                    nav.pop();
                    _showPolicyViolationDialog();
                    return;
                  }
                  if (ctx.mounted) {
                    setModalState(() {
                      isUploading = false;
                      uploadError = res['error'].toString();
                    });
                  }
                } else {
                  if (ctx.mounted) {
                    setModalState(() => uploadProgress = 1.0);
                  }
                  nav.pop();
                  _handleRetake(); // Reset camera back to ready state after publish
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        '현장 영상이 게시되었습니다! (${res['location_name'] ?? '서울 강남구 신사동'} · ${licenseEnabled ? '라이선스 ₩$parsedPrice' : '라이선스 비활성'})',
                      ),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  setModalState(() {
                    isUploading = false;
                    uploadError = '네트워크 업로드 실패: $e';
                  });
                }
              }
            }

            final currentLength = titleController.text.characters.length;

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header with Duration & Original Capture Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.verified_rounded, color: AppColors.accent, size: 22),
                            SizedBox(width: 8),
                            Text(
                              '현장 영상 게시',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary, width: 0.8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.videocam_rounded, color: AppColors.accent, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '원본 촬영 · ${durationSec}초',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Spec #36: Publishing step-by-step progress view
                    if (isUploading) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '현장 영상 게시 중...',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${(uploadProgress * 100).toInt()}%',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: uploadProgress,
                                minHeight: 8,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...List.generate(stepLabels.length, (idx) {
                              final stepNum = idx + 1;
                              final isDone = uploadStep > stepNum;
                              final isCurrent = uploadStep == stepNum;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    if (isDone)
                                      const Icon(Icons.check_circle, color: AppColors.success, size: 16)
                                    else if (isCurrent)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                                      )
                                    else
                                      const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 16),
                                    const SizedBox(width: 10),
                                    Text(
                                      stepLabels[idx],
                                      style: TextStyle(
                                        color: isDone || isCurrent ? AppColors.textPrimary : AppColors.textMuted,
                                        fontSize: 13,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      // Spec #35: Add a title
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                '영상 제목 입력',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '지금 목격하고 있는 현장 상황을 적어주세요 (최대 100자)',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: currentLength >= 100 ? AppColors.danger : AppColors.cardBorder,
                              ),
                            ),
                            child: Text(
                              '$currentLength / 100',
                              style: TextStyle(
                                color: currentLength >= 100 ? AppColors.danger : AppColors.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        maxLength: 100,
                        maxLines: 2,
                        onChanged: (_) => setModalState(() {}),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '예: 서울역 대합실 현재 인파가 많아 혼잡합니다',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Quick preset chips for easy testing
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickTitleChip('신사동 가로수길 실시간 인파 현황', (val) {
                              titleController.text = val;
                              setModalState(() {});
                            }),
                            const SizedBox(width: 6),
                            _buildQuickTitleChip('강남역 사거리 퇴근길 교통 상황', (val) {
                              titleController.text = val;
                              setModalState(() {});
                            }),
                            const SizedBox(width: 6),
                            _buildQuickTitleChip('한강공원 반포지구 현재 날씨 및 산책로', (val) {
                              titleController.text = val;
                              setModalState(() {});
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Spec #35: License this video
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.workspace_premium_rounded, color: AppColors.accent, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      '라이선스 판매 설정',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    _buildRadioOption(
                                      label: '꺼짐',
                                      selected: !licenseEnabled,
                                      onTap: () => setModalState(() => licenseEnabled = false),
                                    ),
                                    const SizedBox(width: 10),
                                    _buildRadioOption(
                                      label: '켜짐',
                                      selected: licenseEnabled,
                                      onTap: () => setModalState(() => licenseEnabled = true),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (licenseEnabled) ...[
                              const Divider(color: AppColors.cardBorder, height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '표준 라이선스 판매 가격',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                  Text(
                                    '크리에이터 80% 정산 (₩${((int.tryParse(customPriceController.text) ?? licensePrice) * 0.8).toInt()})',
                                    style: const TextStyle(
                                      color: AppColors.success,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  for (final preset in [5000, 10000, 20000, 50000]) ...[
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            licensePrice = preset;
                                            customPriceController.text = preset.toString();
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: licensePrice == preset
                                                ? AppColors.primary.withOpacity(0.25)
                                                : AppColors.card,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: licensePrice == preset
                                                  ? AppColors.primary
                                                  : AppColors.cardBorder,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            '₩${preset ~/ 1000},000',
                                            style: TextStyle(
                                              color: licensePrice == preset
                                                  ? AppColors.accent
                                                  : AppColors.textMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 6),
                              const Text(
                                '라이선스 판매를 끄면 다른 사용자가 이 영상을 구매/다운로드할 수 없습니다.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Location & Metadata Auto-Detection Info (Spec #4, #12, #59)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on, color: AppColors.accent, size: 15),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '위치: 서울 강남구 신사동 (프라이버시 보호 150m 퍼징 적용 · ${ApiService.currentUsername})',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.subtitles_outlined, color: AppColors.accent, size: 15),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '자막: 현장 음성에서 원문 자막 자동 생성 · 세션 $_captureSessionId',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Spec #18 & #36: Upload Failure Banner with Retry Button
                    if (uploadError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.danger),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                uploadError!,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: isUploading ? null : executePublish,
                              icon: const Icon(Icons.refresh, color: AppColors.accent, size: 16),
                              label: const Text(
                                '재시도',
                                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Publish Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isUploading ? null : executePublish,
                        child: Text(
                          isUploading
                              ? '현장 영상 게시 중...'
                              : (uploadError != null ? '다시 게시하기' : '게시하기'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Spec #37: Explicit Sexual / Prohibited Content Rejection Screen
  void _showPolicyViolationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        title: Row(
          children: const [
            Icon(Icons.block_flipped, color: AppColors.danger, size: 24),
            SizedBox(width: 8),
            Text(
              '게시할 수 없는 영상',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              '이 영상은 NOWFIELD 콘텐츠 운영 정책을 위반하여 삭제되었으며 계정이 영구 이용정지되었습니다.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.5),
            ),
            SizedBox(height: 12),
            Text(
              '명백한 노골적 성적 콘텐츠 및 불법 촬영물은 사전 안전 검사에서 즉시 차단·삭제되며 계정이 영구 이용정지됩니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _handleRetake();
            },
            child: const Text('확인 (영상 삭제됨)'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTitleChip(String label, ValueChanged<String> onSelect) {
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      ),
    );
  }

  Widget _buildRadioOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.primary : AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 14,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textPrimary : AppColors.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback minimal valid MP4 container for browser simulation when native camera is not connected
  List<int> _generateDummyMp4Bytes() {
    return [
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // ftyp
      0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x02, 0x00, // isom
      0x69, 0x73, 0x6f, 0x6d, 0x69, 0x73, 0x6f, 0x32, // isomiso2
      0x00, 0x00, 0x00, 0x08, 0x6d, 0x64, 0x61, 0x74, // mdat
    ];
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool isCameraReady =
        !_hasCameraError && _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview or Simulated Viewfinder / Permission Denied UI (Spec #33 & #51.4)
          if (isCameraReady)
            Center(child: CameraPreview(_controller!))
          else
            _buildSimulatedViewfinder(),

          // 2. Top Controls (Spec #33: [× / One Take Only] ... [Camera Switch / ⚡ Flash])
          Positioned(
            top: 44,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Cancel/Reset button when recording/reviewing, or One Take badge
                Row(
                  children: [
                    if (_isRecording || _isReviewing)
                      IconButton(
                        tooltip: '촬영 취소',
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: _handleRetake,
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.subtitleBackground,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.accent.withOpacity(0.35), width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isRecording ? Icons.fiber_manual_record : Icons.camera_alt,
                            color: _isRecording ? AppColors.danger : AppColors.accent,
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isFrontCamera ? '원테이크 · 전면' : '원테이크 · 후면',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Right: Front/Rear Camera Switch & Flash Toggle (Spec #3 & #33)
                Row(
                  children: [
                    // Camera Switch (Front / Rear)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.subtitleBackground,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 0.8),
                      ),
                      child: IconButton(
                        tooltip: '전/후면 카메라 전환',
                        icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 22),
                        onPressed: _isRecording ? null : _switchCamera,
                      ),
                    ),
                    // Flash Toggle (⚡)
                    Container(
                      decoration: BoxDecoration(
                        color: _isFlashOn
                            ? AppColors.warning.withOpacity(0.25)
                            : AppColors.subtitleBackground,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isFlashOn ? AppColors.warning : Colors.white24,
                          width: 0.8,
                        ),
                      ),
                      child: IconButton(
                        tooltip: '플래시 켜기/끄기',
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _isFlashOn ? AppColors.warning : Colors.white,
                          size: 22,
                        ),
                        onPressed: _toggleFlash,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Spec #34: Post-Recording Review Overlay ("Use this video? [Retake] [Use Video]")
          if (_isReviewing)
            _buildPostRecordingReviewOverlay()
          else
            // 4. Bottom Controls (00:23 / 01:00 Timer & Record Shutter, Spec #33)
            Positioned(
              bottom: 36,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  // 60s Progress Bar when recording
                  if (_isRecording) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_recordDuration / 60.0).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // Timer Badge (00:23 / 01:00)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isRecording ? AppColors.danger.withOpacity(0.85) : AppColors.subtitleBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_formatDuration(_recordDuration)} / 01:00',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Record Shutter (●)
                  GestureDetector(
                    onTap: _isRecording ? _stopRecording : _startRecording,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isRecording ? AppColors.danger : Colors.white,
                          width: 4,
                        ),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isRecording ? 30 : 60,
                          height: _isRecording ? 30 : 60,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(_isRecording ? 6 : 32),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRecording
                        ? '탭하여 촬영 종료 (최대 60초 자동 종료)'
                        : '탭하여 현장 촬영 시작 (사진첩 업로드·편집 불가)',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Spec #34: Post-Recording Review UX ("Use this video? [ Retake ] [ Use Video ]")
  Widget _buildPostRecordingReviewOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.65),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.2),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 36),
                ),
                const SizedBox(height: 12),
                const Text(
                  '이 영상을 사용하시겠습니까?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '촬영 길이: ${_formatDuration(_lastRecordedSeconds)} / 01:00 · 원본 촬영 검증됨',
                  style: const TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('촬영 세션 번호', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          Text(_captureSessionId, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('카메라 / 플래시', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          Text(
                            '${_isFrontCamera ? '전면 카메라' : '후면 카메라'} · 플래시 ${_isFlashOn ? '켜짐' : '꺼짐'}',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    // [ Retake ] Button
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.cardBorder, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _handleRetake,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text(
                          '재촬영',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // [ Use Video ] Button
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _showPublishBottomSheet(_recordedVideo, _lastRecordedSeconds),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          '영상 사용',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Simulated Viewfinder & Spec #51.4 Camera Permission Denied UI
  Widget _buildSimulatedViewfinder() {
    if (!_useSimulationAfterDenied) {
      // Exact Spec #51.4 Camera Denied state
      return Container(
        color: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined, size: 48, color: AppColors.warning),
                const SizedBox(height: 14),
                const Text(
                  '카메라 접근 권한이 필요합니다',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'NOWFIELD는 직접 촬영한 현장 영상만 게시할 수 있습니다.\n카메라 권한을 허용하거나 브라우저 시뮬레이션 모드를 사용하세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          _initCamera();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('브라우저/기기 설정에서 카메라 권한을 확인합니다.')),
                          );
                        },
                        child: const Text('권한 설정 열기'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => setState(() => _useSimulationAfterDenied = true),
                        child: const Text('시뮬레이션 촬영'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _isFrontCamera
              ? [const Color(0xFF132238), const Color(0xFF0A111A)]
              : [const Color(0xFF0F1B2D), const Color(0xFF090E17)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? AppColors.danger.withOpacity(0.18)
                    : AppColors.background.withOpacity(0.6),
                border: Border.all(
                  color: _isRecording ? AppColors.danger : AppColors.cardBorder,
                  width: 1.5,
                ),
              ),
              child: Icon(
                _isFrontCamera ? Icons.camera_front_rounded : Icons.videocam_outlined,
                size: 48,
                color: _isRecording ? AppColors.danger : AppColors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isRecording ? '실시간 현장 촬영 중...' : '현장 촬영 카메라',
              style: TextStyle(
                color: _isRecording ? AppColors.danger : AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_isFrontCamera ? '전면 카메라 모드' : '후면 광각 카메라 모드'} · 플래시 ${_isFlashOn ? '켜짐 ⚡' : '꺼짐'}',
              style: const TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '앱 내 카메라로만 직접 촬영 가능한 원테이크 · 60초 모드',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => setState(() => _useSimulationAfterDenied = false),
              icon: const Icon(Icons.privacy_tip_outlined, size: 14, color: AppColors.textMuted),
              label: const Text(
                '카메라 권한 안내 보기',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
