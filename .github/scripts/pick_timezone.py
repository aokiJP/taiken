"""いま現地時刻が [from, to) 時のタイムゾーンを1つ選ぶ (スクリーンショットの空の時間帯をそろえるため)。"""
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

low, high = int(sys.argv[1]), int(sys.argv[2])
zones = [
    "Asia/Tokyo", "Asia/Shanghai", "Asia/Bangkok", "Asia/Kolkata", "Asia/Dubai", "Europe/Moscow",
    "Europe/Berlin", "Europe/London", "Atlantic/Azores", "America/Sao_Paulo", "America/New_York",
    "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Anchorage", "Pacific/Honolulu",
    "Pacific/Auckland", "Australia/Sydney",
]
for zone in zones:
    if low <= datetime.now(ZoneInfo(zone)).hour < high:
        print(zone)
        break
else:
    print("Asia/Tokyo")
