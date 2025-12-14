import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/admin_analytics_service.dart';

/// Bar Chart comparing Mint vs Burn operations
/// 
/// Shows daily mint (green bars) vs burn (red bars) to detect inflation/deflation
class MintBurnChart extends StatelessWidget {
  final List<DailyTrend> trends;

  const MintBurnChart({
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
                Icons.bar_chart,
                color: Color(0xFF00FFC3),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Mint vs Burn (7 Days)',
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
              _buildLegendItem('Mint (Inflow)', const Color(0xFF00FFC3)),
              const SizedBox(width: 20),
              _buildLegendItem('Burn (Outflow)', const Color(0xFFFF4081)),
            ],
          ),
          const SizedBox(height: 20),
          
          // Chart
          SizedBox(
            height: 250,
            child: BarChart(
              _buildBarChartData(),
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
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
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

  BarChartData _buildBarChartData() {
    final maxValue = trends.fold<double>(
      0,
      (max, trend) {
        final currentMax = trend.totalMint > trend.totalBurn 
            ? trend.totalMint 
            : trend.totalBurn;
        return currentMax > max ? currentMax : max;
      },
    );

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxValue * 1.2,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          tooltipBgColor: const Color(0xFF2A2F3E),
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final trend = trends[groupIndex];
            final isMint = rodIndex == 0;
            final value = isMint ? trend.totalMint : trend.totalBurn;
            
            return BarTooltipItem(
              '${isMint ? "Mint" : "Burn"}\n\$${_formatValue(value)}',
              TextStyle(
                color: isMint ? const Color(0xFF00FFC3) : const Color(0xFFFF4081),
                fontWeight: FontWeight.bold,
              ),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              if (value.toInt() >= 0 && value.toInt() < trends.length) {
                final date = trends[value.toInt()].date;
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
            interval: maxValue / 5,
            getTitlesWidget: (value, meta) {
              return Text(
                _formatValue(value),
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
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxValue / 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.white.withOpacity(0.1),
            strokeWidth: 1,
          );
        },
      ),
      barGroups: trends.asMap().entries.map((entry) {
        final index = entry.key;
        final trend = entry.value;
        
        return BarChartGroupData(
          x: index,
          barRods: [
            // Mint bar (green)
            BarChartRodData(
              toY: trend.totalMint,
              color: const Color(0xFF00FFC3),
              width: 12,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
            // Burn bar (red)
            BarChartRodData(
              toY: trend.totalBurn,
              color: const Color(0xFFFF4081),
              width: 12,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _formatValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }
}
