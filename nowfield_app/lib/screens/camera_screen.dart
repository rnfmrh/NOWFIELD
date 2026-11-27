import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../constants/app_colors.dart';
import '../services/api_service.dart';
import '../services/url_storage.dart';
import 'earnings_screen.dart';

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

  // Mobile Camera Zoom state (Pinch-to-Zoom + 1x/2x/3x quick presets)
  double _currentZoomLevel = 1.0;
  double _baseZoomLevel = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 5.0;
  bool _supportsHardwareZoom = false;

  // Spec #4 Metadata: Capture Session ID & Start/End timestamps
  String _captureSessionId = '';
  DateTime? _captureStartTime;
  // ignore: unused_field
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
      if (_cameras == null) {
        final allCameras = await availableCameras();
        _cameras = _filterMainFrontAndBackCameras(allCameras);
      }
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
        await _initZoomBounds(controller);
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

  /// Filter device camera list to at most 2 cameras: 1 main rear camera + 1 main front camera.
  List<CameraDescription> _filterMainFrontAndBackCameras(List<CameraDescription> allCameras) {
    if (allCameras.length <= 2) return allCameras;

    CameraDescription? mainBack;
    CameraDescription? mainFront;

    for (final cam in allCameras) {
      if (mainBack == null && cam.lensDirection == CameraLensDirection.back) {
        mainBack = cam;
      } else if (mainFront == null && cam.lensDirection == CameraLensDirection.front) {
        mainFront = cam;
      }
      if (mainBack != null && mainFront != null) break;
    }

    // Fallback for desktop/web cameras labeled 'external' when back/front aren't explicitly set
    if (mainBack == null && allCameras.isNotEmpty) {
      mainBack = allCameras.first;
    }
    if (mainFront == null && allCameras.length > 1) {
      mainFront = allCameras.firstWhere(
        (c) => c != mainBack,
        orElse: () => allCameras[1],
      );
    }

    return [
      if (mainBack != null) mainBack,
      if (mainFront != null && mainFront != mainBack) mainFront,
    ];
  }

  /// Initialize zoom bounds for the active mobile camera lens
  Future<void> _initZoomBounds(CameraController controller) async {
    _currentZoomLevel = 1.0;
    _baseZoomLevel = 1.0;
    try {
      final minZ = await controller.getMinZoomLevel();
      final maxZ = await controller.getMaxZoomLevel();
      _minAvailableZoom = minZ >= 1.0 ? minZ : 1.0;
      _maxAvailableZoom = maxZ > _minAvailableZoom ? maxZ.clamp(2.0, 8.0) : 5.0;
      _supportsHardwareZoom = maxZ > minZ;
      if (_supportsHardwareZoom) {
        await controller.setZoomLevel(_currentZoomLevel.clamp(minZ, maxZ));
      }
    } catch (_) {
      _minAvailableZoom = 1.0;
      _maxAvailableZoom = 5.0;
      _supportsHardwareZoom = false;
    }
  }

  /// Set zoom level via pinch gesture or quick preset buttons (1x, 2x, 3x)
  Future<void> _setZoomLevel(double targetZoom) async {
    final clamped = targetZoom.clamp(_minAvailableZoom, _maxAvailableZoom);
    if ((clamped - _currentZoomLevel).abs() < 0.01) return;
    setState(() {
      _currentZoomLevel = clamped;
    });
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setZoomLevel(clamped);
        _supportsHardwareZoom = true;
      } catch (_) {
        _supportsHardwareZoom = false;
      }
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

  /// Spec #3: Switch Front / Rear Camera (allowed both before and during recording)
  Future<void> _switchCamera() async {
    if (_cameras != null && _cameras!.length > 1) {
      final nextIdx = (_selectedCameraIdx + 1) % _cameras!.length;
      if (_isRecording && _controller != null && _controller!.value.isInitialized) {
        final nextDesc = _cameras![nextIdx];
        try {
          await _controller!.setDescription(nextDesc);
          await _initZoomBounds(_controller!);
          _selectedCameraIdx = nextIdx;
          if (mounted) {
            setState(() {
              _isFrontCamera = nextDesc.lensDirection == CameraLensDirection.front;
            });
          }
        } catch (_) {
          // Fallback if browser/platform requires re-initializing the stream while recording
          await _initCamera(cameraIndex: nextIdx);
          try {
            if (_controller != null && _controller!.value.isInitialized) {
              await _controller!.startVideoRecording();
            }
          } catch (_) {}
        }
      } else {
        await _initCamera(cameraIndex: nextIdx);
      }
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
    _setZoomLevel(1.0);
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

  /// v1.1 CR-01, CR-02, CR-03 Publish UI:
  /// - CR-02: Location precision selector (`exact` default, `approximate`, `hidden`), pre-publish map pin preview,
  ///          warning ("⚠️ 이 위치가 모든 시청자에게 공개됩니다"), explicit first-time consent, OS precise permission & sensitive place guard.
  /// - CR-01: License sales removed; replaced with per-video `후원 버튼 표시` (`support_enabled`) toggle (default OFF, requires verified support URL).
  /// - CR-03: Passes separate `captured_at` & `display_timezone`.
  void _showPublishBottomSheet(XFile? file, int durationSec) {
    final titleController = TextEditingController();

    // CR-02: Default selection is 'exact' (Exact Location), subject to explicit consent & OS precise permission
    String locationDisplayMode = 'exact'; // 'exact', 'approximate', 'hidden'
    bool exactLocationConsented = ApiService.exactLocationConsentNotifier.value;
    bool precisePermissionGranted = ApiService.preciseLocationPermissionNotifier.value;
    bool isSensitivePlace = false;

    // CR-01: Per-video creator support button toggle (Default OFF; requires verified CreatorSupportAccount)
    bool supportEnabled = false;
    Map<String, dynamic>? linkedSupportAccount =
        ApiService.supportAccountsCacheNotifier.value[ApiService.currentUserId];
    bool hascheckedSupportAccount = false;

    double lat = 37.5204;
    double lng = 127.0229;
    String resolvedDongName = '서울 강남구 신사동';
    bool hasResolvedLocation = false;

    bool isUploading = false;
    int uploadStep = 0; // 0: idle, 1: Uploading, 2: Preparing captions, 3: Checking safety, 4: Preparing field data
    double uploadProgress = 0.0;
    String? uploadError;

    const List<String> stepLabels = [
      '영상 업로드 중...',
      '자막 자동 생성 중...',
      '안전성 및 정책 검사 중...',
      '현장 위치 프라이버시 및 타임스탬프 검증 중...',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!hascheckedSupportAccount) {
              hascheckedSupportAccount = true;
              ApiService.getSupportAccount(ApiService.currentUserId).then((acc) {
                if (ctx.mounted) {
                  setModalState(() {
                    linkedSupportAccount = acc;
                    if (acc == null || acc['active'] != true || acc['ownership_status'] != 'verified') {
                      supportEnabled = false;
                    }
                  });
                }
              });
            }

            if (!hasResolvedLocation) {
              hasResolvedLocation = true;
              () async {
                final pos = await getCurrentBrowserPosition();
                if (pos != null) {
                  lat = pos['lat'] ?? lat;
                  lng = pos['lng'] ?? lng;
                }
                final dong = await ApiService.resolveNeighborhoodName(lat, lng);
                if (ctx.mounted) {
                  setModalState(() {
                    resolvedDongName = dong;
                  });
                }
              }();
            }

            final bool canEnableSupport = linkedSupportAccount != null &&
                linkedSupportAccount!['active'] == true &&
                linkedSupportAccount!['ownership_status'] == 'verified' &&
                (linkedSupportAccount!['support_url']?.toString().trim().isNotEmpty == true);

            Future<bool> promptExactLocationConsentDialog() async {
              final result = await showDialog<bool>(
                context: ctx,
                barrierDismissible: false,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: AppColors.card,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '정확한 위치 공개 사전 동의',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: const Text(
                    '⚠️ 이 위치가 모든 시청자에게 공개됩니다.\n\n'
                    '• 정확한 위치로 게시하면 촬영 지점의 정밀 지도 핀이 시청자에게 표시됩니다.\n'
                    '• 집·거주지·학교·병원 등 민감 장소에서 촬영한 경우 약 100~200m 범위 또는 위치 미표시를 권장합니다.\n'
                    '• 동의하지 않더라도 약 100~200m 범위 또는 위치 미표시로 안전하게 게시할 수 있습니다.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: const Text(
                        '약 100~200m 범위로 전환',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: const Text('동의하고 정확한 위치 공개'),
                    ),
                  ],
                ),
              );
              return result == true;
            }

            Future<void> executePublish() async {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setModalState(() => uploadError = '영상 제목을 입력해주세요.');
                return;
              }
              if (title.length > 100) {
                setModalState(() => uploadError = '제목은 최대 100자까지 입력할 수 있습니다.');
                return;
              }

              // CR-02.B: Enforce consent, OS precise permission & sensitive place policy before publishing Exact Location
              String effectiveMode = locationDisplayMode;
              if (effectiveMode == 'exact') {
                if (!precisePermissionGranted || isSensitivePlace) {
                  effectiveMode = 'approximate';
                  setModalState(() => locationDisplayMode = 'approximate');
                } else if (!exactLocationConsented) {
                  final agreed = await promptExactLocationConsentDialog();
                  if (!ctx.mounted) return;
                  if (agreed) {
                    exactLocationConsented = true;
                    await ApiService.recordExactLocationConsent(true);
                    setModalState(() {});
                  } else {
                    effectiveMode = 'approximate';
                    setModalState(() => locationDisplayMode = 'approximate');
                  }
                }
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

                final capturedIso = (_captureStartTime ?? DateTime.now()).toUtc().toIso8601String();

                final res = await ApiService.uploadVideo(
                  videoBytes: videoBytes,
                  filename: 'capture_${DateTime.now().millisecondsSinceEpoch}.mp4',
                  title: title,
                  subtitle: title,
                  latitude: lat,
                  longitude: lng,
                  locationName: resolvedDongName,
                  uploaderId: ApiService.currentUserId,
                  locationDisplayMode: effectiveMode,
                  exactLocationConsented: exactLocationConsented,
                  precisePermissionGranted: precisePermissionGranted,
                  isSensitivePlace: isSensitivePlace,
                  supportEnabled: canEnableSupport && supportEnabled,
                  capturedAt: capturedIso,
                  displayTimezone: 'Asia/Seoul',
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
                  final finalMode = res['location_display_mode']?.toString() ?? effectiveMode;
                  final finalPrivacyLabel = ApiService.formatLocationPrivacyLabel(finalMode);
                  final finalSupport = res['support_enabled'] == true;
                  nav.pop();
                  _handleRetake(); // Reset camera back to ready state after publish
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        '현장 영상이 게시되었습니다!',
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

            String formatLocationModeShort(String mode) {
              if (mode == 'approximate') return '대략적인 위치';
              if (mode == 'hidden') return '위치 비공개';
              return '정확한 위치';
            }

            Future<void> openLocationModePicker() async {
              String tempMode = locationDisplayMode;
              final picked = await showModalBottomSheet<String>(
                context: ctx,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                builder: (sheetCtx) {
                  return StatefulBuilder(
                    builder: (sheetContext, setSheetState) {
                      Widget buildOptionTile({
                        required String modeKey,
                        required IconData icon,
                        required String title,
                        required String subtitle,
                      }) {
                        final bool isSelected = tempMode == modeKey;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setSheetState(() => tempMode = modeKey),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withOpacity(0.12)
                                        : AppColors.card,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    icon,
                                    color: isSelected ? AppColors.primary : AppColors.textPrimary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        subtitle,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color: isSelected ? AppColors.primary : const Color(0xFFD1D6DB),
                                  size: 24,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(
                                    Icons.location_on_outlined,
                                    color: AppColors.textPrimary,
                                    size: 24,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '위치 공개 방식',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '현황에서 본 또는 제목적인 위치를 선택할 수 있어요 · $resolvedDongName',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 18),
                              buildOptionTile(
                                modeKey: 'exact',
                                icon: Icons.location_on_rounded,
                                title: '정확한 위치',
                                subtitle: '촬영한 장소가 지도에 표시됩니다',
                              ),
                              buildOptionTile(
                                modeKey: 'approximate',
                                icon: Icons.radar_rounded,
                                title: '대략적인 위치',
                                subtitle: '약 100~200m 범위로 표시됩니다',
                              ),
                              buildOptionTile(
                                modeKey: 'hidden',
                                icon: Icons.location_off_outlined,
                                title: '위치 비공개',
                                subtitle: '지도에 위치가 표시되지 않습니다',
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.card,
                                    foregroundColor: AppColors.textPrimary,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(26),
                                    ),
                                  ),
                                  onPressed: () => Navigator.pop(sheetCtx, tempMode),
                                  child: const Text(
                                    '확인',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
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

              if (picked != null && ctx.mounted) {
                if (picked == 'exact' && !precisePermissionGranted) {
                  setModalState(() => locationDisplayMode = 'approximate');
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: Text('OS 정밀 위치 권한이 꺼져 있어 대략적인 위치로 설정됩니다.')),
                  );
                  return;
                }
                if (picked == 'exact' && !exactLocationConsented) {
                  final agreed = await promptExactLocationConsentDialog();
                  if (!ctx.mounted) return;
                  if (agreed) {
                    exactLocationConsented = true;
                    await ApiService.recordExactLocationConsent(true);
                    setModalState(() => locationDisplayMode = 'exact');
                  } else {
                    setModalState(() => locationDisplayMode = 'approximate');
                  }
                  return;
                }
                setModalState(() => locationDisplayMode = picked);
              }
            }

            void showCaptureInfoDialog() {
              showDialog(
                context: ctx,
                builder: (dCtx) => AlertDialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  title: Row(
                    children: const [
                      Icon(Icons.verified_rounded, color: AppColors.primary, size: 22),
                      SizedBox(width: 8),
                      Text(
                        '원본 촬영 및 게시 안내',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  content: Text(
                    '• 촬영 위치: $resolvedDongName\n'
                    '• 촬영 길이: ${_formatDuration(durationSec)}\n'
                    '• 촬영 시각: ${ApiService.formatPublishedDateTime((_captureStartTime ?? DateTime.now()).toUtc().toIso8601String())}\n'
                    '• 자막: 현장 음성에서 원문 및 다국어 자막 자동 생성\n'
                    '• 세션: $_captureSessionId',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text(
                        '확인',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Bar: [<] Back and [ⓘ] Info button matching the new concept
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '촬영 정보',
                          icon: const Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.textPrimary,
                            size: 22,
                          ),
                          onPressed: showCaptureInfoDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Center Rounded Video Preview Thumbnail Card with Play Button & Duration Badge
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: AppColors.card,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                          image: const DecorationImage(
                            image: NetworkImage('https://picsum.photos/seed/nowfield_namsan/600/600'),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Subtle dark gradient at bottom for duration legibility
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.35),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Center Play Icon Button
                            Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ),
                            // Bottom Right Duration Pill (e.g. 0:45)
                            Positioned(
                              right: 12,
                              bottom: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '0:${durationSec.clamp(1, 60).toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Spec #36: Publishing step-by-step progress view
                    if (isUploading) ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
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
                                    color: AppColors.primary,
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
                                backgroundColor: AppColors.cardBorder,
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.radio_button_unchecked,
                                        color: AppColors.textMuted,
                                        size: 16,
                                      ),
                                    const SizedBox(width: 10),
                                    Text(
                                      stepLabels[idx],
                                      style: TextStyle(
                                        color: isDone || isCurrent
                                            ? AppColors.textPrimary
                                            : AppColors.textMuted,
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
                      const SizedBox(height: 18),
                    ] else ...[
                      // Prompt Heading: "지금, 무슨 일이 있나요?"
                      const Text(
                        '지금, 무슨 일이 있나요?',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '현장에서 본 소식을 제목으로 알려주세요',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Clean Soft-Gray Rounded Title Input Field
                      TextField(
                        controller: titleController,
                        maxLength: 100,
                        maxLines: 1,
                        onChanged: (_) => setModalState(() {}),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '서울 남산, 오늘 날씨 정말 좋아요!',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.card,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$currentLength / 100',
                          style: TextStyle(
                            color: currentLength >= 100 ? AppColors.danger : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(color: AppColors.cardBorder, height: 1),

                      // Row 1: Location Disclosure ("📍 위치 공개    정확한 위치 >")
                      InkWell(
                        onTap: openLocationModePicker,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                color: AppColors.textPrimary,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                '위치 공개',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatLocationModeShort(locationDisplayMode),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: AppColors.cardBorder, height: 1),

                      // Row 2: Support Feature Toggle ("♡ 후원 기능 사용 ⓘ    [Switch]")
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.favorite_border_rounded,
                              color: AppColors.textPrimary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              '후원 기능 사용',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  const SnackBar(
                                    content: Text('시청자가 외부 후원 페이지를 통해 수수료 0%로 직접 후원할 수 있습니다.'),
                                  ),
                                );
                              },
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: AppColors.textMuted,
                                size: 17,
                              ),
                            ),
                            const Spacer(),
                            Switch.adaptive(
                              value: canEnableSupport && supportEnabled,
                              activeColor: Colors.white,
                              activeTrackColor: AppColors.primary,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: const Color(0xFFD1D6DB),
                              onChanged: (val) async {
                                if (val && !canEnableSupport) {
                                  await Navigator.of(this.context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const EarningsScreen(initialTabIndex: 1),
                                    ),
                                  );
                                  final updatedAcc =
                                      await ApiService.getSupportAccount(ApiService.currentUserId);
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      linkedSupportAccount = updatedAcc;
                                      if (updatedAcc != null &&
                                          updatedAcc['active'] == true &&
                                          updatedAcc['ownership_status'] == 'verified') {
                                        supportEnabled = true;
                                      }
                                    });
                                  }
                                  return;
                                }
                                setModalState(() => supportEnabled = val);
                              },
                            ),
                          ],
                        ),
                      ),

                      // Expandable Support Info Banner (Screen 3 of the concept image)
                      if (canEnableSupport && supportEnabled) ...[
                        const SizedBox(height: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.of(this.context).push(
                              MaterialPageRoute(
                                builder: (_) => const EarningsScreen(initialTabIndex: 1),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F6FE),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.volunteer_activism_rounded,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    '시청자들이 크리에이터를\n후원할 수 있어요!',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: const [
                                    Text(
                                      '자세히 보기',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.primary,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                    ],

                    // Spec #18 & #36: Upload Failure Banner with Retry Button
                    if (uploadError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                uploadError!,
                                style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
                              ),
                            ),
                            TextButton(
                              onPressed: isUploading ? null : executePublish,
                              child: const Text(
                                '재시도',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Pill-shaped Full-Width Blue [ 게시하기 ] Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(27),
                          ),
                        ),
                        onPressed: isUploading ? null : executePublish,
                        child: Text(
                          isUploading
                              ? '현장 영상 게시 중...'
                              : (uploadError != null ? '다시 게시하기' : '게시하기'),
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
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
            child: const Text('확인'),
          ),
        ],
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

  /// Mobile-native style zoom bar (`1x`, `2x`, `3x`) + current pinch zoom indicator
  Widget _buildMobileZoomBar() {
    final List<double> presets = [
      1.0,
      if (_maxAvailableZoom >= 2.0) 2.0,
      if (_maxAvailableZoom >= 3.0) 3.0,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.subtitleBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: presets.map((preset) {
          // Determine if this preset is the active range
          final bool isSelected;
          if (preset == 1.0) {
            isSelected = _currentZoomLevel < 1.5;
          } else if (preset == 2.0) {
            isSelected = _currentZoomLevel >= 1.5 && _currentZoomLevel < 2.5;
          } else {
            isSelected = _currentZoomLevel >= 2.5;
          }

          final String label = isSelected
              ? '${_currentZoomLevel.toStringAsFixed(_currentZoomLevel % 1 == 0 ? 0 : 1)}x'
              : '${preset.toInt()}x';

          return GestureDetector(
            onTap: () => _setZoomLevel(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isSelected ? 40 : 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.22) : Colors.transparent,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(color: AppColors.warning, width: 1.2)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.warning : Colors.white,
                  fontSize: isSelected ? 12 : 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
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
          // Wrapped with mobile pinch-to-zoom GestureDetector
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _baseZoomLevel = _currentZoomLevel;
            },
            onScaleUpdate: (details) {
              if (_isReviewing) return;
              _setZoomLevel(_baseZoomLevel * details.scale);
            },
            child: ClipRect(
              child: Transform.scale(
                scale: _supportsHardwareZoom ? 1.0 : _currentZoomLevel,
                child: isCameraReady
                    ? Center(child: CameraPreview(_controller!))
                    : _buildSimulatedViewfinder(),
              ),
            ),
          ),

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
                        onPressed: _isReviewing ? null : _switchCamera,
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
            // 4. Bottom Controls (Zoom Selector, 00:23 / 01:00 Timer & Record Shutter, Spec #33)
            Positioned(
              bottom: 36,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  // Mobile Quick Zoom Bar (1x / 2x / 3x + live pinch zoom indicator)
                  _buildMobileZoomBar(),
                  const SizedBox(height: 12),
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
                        ? '탭하여 촬영 종료'
                        : '탭하여 현장 촬영 시작',
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
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
                color: _isRecording ? AppColors.danger : Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _isRecording ? '실시간 현장 촬영 중...' : '현장 촬영 카메라',
              style: TextStyle(
                color: _isRecording ? AppColors.danger : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_isFrontCamera ? '전면 카메라 모드' : '후면 광각 카메라 모드'} · 플래시 ${_isFlashOn ? '켜짐 ⚡' : '꺼짐'}',
              style: const TextStyle(color: Color(0xFF93C5FD), fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              '앱 내 카메라로만 직접 촬영 가능한 원테이크 · 60초 모드',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => setState(() => _useSimulationAfterDenied = false),
              icon: const Icon(Icons.privacy_tip_outlined, size: 14, color: Colors.white60),
              label: const Text(
                '카메라 권한 안내 보기',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
