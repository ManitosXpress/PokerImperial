import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/admin_analytics_service.dart';

/// Line Chart showing 7-day evolution of Liquidity vs Rake
/// 
/// Displays two lines:
/// - Blue: Total Liquidity (left Y-axis)
/// - Green: Total Rake (right Y-axis)
class LiquidityRakeChart extends StatelessWidget {
  final List<DailyTrend> trends;

  const LiquidityRakeChart({
    Key? key,
    required this.trends,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) {
      return const Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00FFC3).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              const Icon(
                Icons.show_chart,
                color: Color(0xFF00FFC3),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Liquidity vs Rake (7 Days)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Legend
          Row(
            children: [
              _buildLegendItem('Liquidity', const Color(0xFF00A8FF)),
              const SizedBox(width: 20),
              _buildLegendItem('Rake', const Color(0xFF00FFC3)),
            ],
          ),
          const SizedBox(height: 20),
          
          // Chart
          SizedBox(
            height: 250,
            child: LineChart(
              _buildLineChartData(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  LineChartData _buildLineChartData() {
    // Calculate min and max values for scaling
    double maxLiquidity = trends
        .map((t) => t.totalLiquidity)
        .reduce((a, b) => a > b ? a : b);
    double maxRake = trends
        .map((t) => t.totalRake)
        .reduce((a, b) => a > b ? a : b);

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxLiquidity / 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.white.withOpacity(0.1),
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1,
            getTitlesWidget: (value, meta) {
              if (value.toInt() >= 0 && value.toInt() < trends.length) {
                final date = trends[value.toInt()].date;
                // Show MM/DD format
                final parts = date.split('-');
                if (parts.length == 3) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${parts[1]}/${parts[2]}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            interval: maxLiquidity / 5,
            getTitlesWidget: (value, meta) {
              return Text(
                _formatAxisValue(value),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (trends.length - 1).toDouble(),
      minY: 0,
      maxY: maxLiquidity * 1.1,
      lineBarsData: [
        // Liquidity line (blue)
        LineChartBarData(
          spots: trends.asMap().entries.map((entry) {
            return FlSpot(entry.key.toDouble(), entry.value.totalLiquidity);
          }).toList(),
          isCurved: true,
          color: const Color(0xFF00A8FF),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: const Color(0xFF00A8FF),
                strokeWidth: 2,
                strokeColor: const Color(0xFF1A1F2E),
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF00A8FF).withOpacity(0.1),
          ),
        ),
        
        // Rake line (green) - scaled to fit on same axis
        LineChartBarData(
          spots: trends.asMap().entries.map((entry) {
            // Scale rake to fit on liquidity axis
            final scaledRake = entry.value.totalRake * (maxLiquidity / maxRake);
            return FlSpot(entry.key.toDouble(), scaledRake);
          }).toList(),
          isCurved: true,
          color: const Color(0xFF00FFC3),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: const Color(0xFF00FFC3),
                strokeWidth: 2,
                strokeColor: const Color(0xFF1A1F2E),
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF00FFC3).withOpacity(0.1),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: const Color(0xFF2A2F3E),
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final trendIndex = barSpot.x.toInt();
              if (trendIndex >= 0 && trendIndex < trends.length) {
                final trend = trends[trendIndex];
                final isLiquidity = barSpot.barIndex == 0;
                
                return LineTooltipItem(
                  isLiquidity
                      ? 'Liquidity: \$${_formatAxisValue(trend.totalLiquidity)}'
                      : 'Rake: \$${_formatAxisValue(trend.totalRake)}',
                  TextStyle(
                    color: isLiquidity 
                        ? const Color(0xFF00A8FF) 
                        : const Color(0xFF00FFC3),
                    fontWeight: FontWeight.bold,
                  ),
                );
              }
              return null;
            }).toList();
          },
        ),
      ),
    );
  }

  String _formatAxisValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }
}
