/// Dates the way people say them: "Thu 5 Nov", with the year only when it
/// isn't this year, and "Today" / "Yesterday" / "Tomorrow" when close.
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String niceTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String niceDate(DateTime d, {bool time = false, bool relative = true}) {
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final day = relative && days == 0
      ? 'Today'
      : relative && days == -1
          ? 'Yesterday'
          : relative && days == 1
              ? 'Tomorrow'
              : '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
  return time ? '$day, ${niceTime(d)}' : day;
}
