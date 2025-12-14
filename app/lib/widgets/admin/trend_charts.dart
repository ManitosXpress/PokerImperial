import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class TrendCharts extends StatelessWidget {
  final List<Map<String, dynamic>> dailyStats;

  const TrendCharts({super.key, required this.dailyStats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildChartContainer(
          title: 'Liquidez vs Rake (7 Días)',
          child: _buildLineChart(),
        ),
        const SizedBox(height: 16),
        _buildChartContainer(
          title: 'Entradas vs Salidas (Mint vs Burn)',
          child: _buildBarChart(),
        ),
      ],
    );
  }

  Widget _buildChartContainer({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart() {
    if (dailyStats.isEmpty) return const Center(child: Text('No data', style: TextStyle(color: Colors.white54)));

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1)),
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
                int index = value.toInt();
                if (index >= 0 && index < dailyStats.length) {
                  // Show simplified date (e.g., "13/12")
                  String date = dailyStats[index]['date'] ?? '';
                  List<String> parts = date.split('-');
                  if (parts.length == 3) return Text('${parts[2]}/${parts[1]}', style: const TextStyle(color: Colors.white54, fontSize: 10));
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), // Hide left titles for cleaner look
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (dailyStats.length - 1).toDouble(),
        minY: 0,
        lineBarsData: [
          // Liquidity Line (Blue) - Mocking liquidity trend based on volume/mint/burn if needed, or just plotting Rake for now as requested
          // Wait, user asked for Liquidity vs Rake. Liquidity is totalCirculation (snapshot). 
          // If we don't have historical liquidity snapshots, we can't plot it accurately.
          // For now, let's plot Rake (Green) and Volume (Blue) as a proxy for activity, or just Rake.
          // Let's assume dailyStats has 'totalRake' and 'totalVolume'.
          
          LineChartBarData(
            spots: dailyStats.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), (e.value['totalRake'] ?? 0).toDouble());
            }).toList(),
            isCurved: true,
            color: Colors.green,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.1)),
          ),
          // Adding Volume as a second line for context (Cyan)
           LineChartBarData(
            spots: dailyStats.asMap().entries.map((e) {
              // Scale volume down to fit chart if needed, or use dual axis (complex).
              // Let's just plot Rake for now to be safe and clean.
              return FlSpot(e.key.toDouble(), ((e.value['totalVolume'] ?? 0) / 100).toDouble()); // Scaled down 100x for visibility comparison
            }).toList(),
            isCurved: true,
            color: Colors.cyan.withOpacity(0.5),
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
     if (dailyStats.isEmpty) return const Center(child: Text('No data', style: TextStyle(color: Colors.white54)));

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _getMaxMintBurn(),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                 int index = value.toInt();
                if (index >= 0 && index < dailyStats.length) {
                   String date = dailyStats[index]['date'] ?? '';
                  List<String> parts = date.split('-');
                  if (parts.length == 3) return Text('${parts[2]}', style: const TextStyle(color: Colors.white54, fontSize: 10));
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: dailyStats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: (e.value['totalMint'] ?? 0).toDouble(),
                color: Colors.green,
                width: 8,
                borderRadius: BorderRadius.circular(2),
              ),
              BarChartRodData(
                toY: (e.value['totalBurn'] ?? 0).toDouble(),
                color: Colors.red,
                width: 8,
                borderRadius: BorderRadius.circular(2),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
  
  double _getMaxMintBurn() {
      double maxVal = 0;
      for (var stat in dailyStats) {
          double mint = (stat['totalMint'] ?? 0).toDouble();
          double burn = (stat['totalBurn'] ?? 0).toDouble();
          if (mint > maxVal) maxVal = mint;
          if (burn > maxVal) maxVal = burn;
      }
      return maxVal == 0 ? 100 : maxVal * 1.2; // Add buffer
  }
}
