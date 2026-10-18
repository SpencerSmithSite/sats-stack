/// Which slice of history the stack chart shows.
///
/// Lives here rather than in the screen because the chart and the period chips
/// both need it, and they moved out.
library;

enum StackPeriod { threeM, sixM, oneY, all }

extension StackPeriodLabel on StackPeriod {
  String get label => switch (this) {
        StackPeriod.threeM => '3M',
        StackPeriod.sixM => '6M',
        StackPeriod.oneY => '1Y',
        StackPeriod.all => 'All',
      };
}
