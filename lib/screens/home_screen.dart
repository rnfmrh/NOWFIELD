import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'NOWFIELD',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            fontSize: 22,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: () {},
          ),
        ],
      ),
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: 5,
        itemBuilder: (context, index) {
          return VideoFeedItem(index: index);
        },
      ),
    );
  }
}

class VideoFeedItem extends StatelessWidget {
  final int index;
  const VideoFeedItem({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Simulated Video Background
        Image.network(
          'https://picsum.photos/seed/${index + 10}/800/1600',
          fit: BoxFit.cover,
        ),
        
        // Gradient overlay for better text visibility
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black45,
                Colors.black87,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.6, 0.8, 1.0],
            ),
          ),
        ),

        // Content
        SafeArea(
          child: Stack(
            children: [
              // Top Left Title
              const Positioned(
                top: 20,
                left: 16,
                right: 60,
                child: Text(
                  'Seoul Station is really crowded right now! Everyone is going home.',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Subtitles area (Center Bottom)
              Positioned(
                bottom: 110,
                left: 16,
                right: 70, // Leave space for actions
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: const Text(
                    'People are rushing towards the subway. It looks like a huge event just ended.',
                    style: TextStyle(color: Colors.white, fontSize: 16, height: 1.3),
                  ),
                ),
              ),

              // Bottom Left User Info
              Positioned(
                bottom: 20,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundImage: NetworkImage('https://i.pravatar.cc/100?img=3'),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          '@seoul_walker',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Original Capture',
                            style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Seoul · 3 min ago',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right Actions
              Positioned(
                bottom: 20,
                right: 8,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildActionIcon(Icons.thumb_up_rounded, '12K'),
                    _buildActionIcon(Icons.chat_bubble_rounded, '342'),
                    _buildActionIcon(Icons.monetization_on_rounded, 'License'),
                    _buildActionIcon(Icons.share_rounded, 'Share'),
                    const SizedBox(height: 10),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white, size: 30),
                      onPressed: () => _showMoreBottomSheet(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionIcon(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 32),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildBottomSheetItem(Icons.bookmark_border, 'Save'),
              _buildBottomSheetItem(Icons.report_outlined, 'Report', color: Colors.redAccent),
              _buildBottomSheetItem(Icons.block, 'Block User'),
              _buildBottomSheetItem(Icons.visibility_off, 'Not Interested'),
            ],
          ),
        );
      }
    );
  }

  Widget _buildBottomSheetItem(IconData icon, String title, {Color color = Colors.white}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color, fontSize: 16)),
      onTap: () {},
    );
  }
}
