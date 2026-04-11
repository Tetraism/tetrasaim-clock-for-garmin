import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Timer;
import Toybox.Application;
import Toybox.Application.Properties;

class decimal_clock_for_garminView extends WatchUi.WatchFace {


    var _timer as Timer.Timer?;

    function initialize() {
        WatchFace.initialize();
        _timer = null;
    }

    function onLayout(dc as Dc) as Void {
    }

    function onShow() as Void {
        _timer = new Timer.Timer();
        (_timer as Timer.Timer).start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    // Returns [dayOfMonth 1-30, monthIndex 0-11] for regular days,
    // or [bonusIndex 0-4, -1] for the 5 bonus days at year-end.
    // Calendar: 12 months x 5 weeks x 6 days = 360 days + 5 bonus days.
    // Synced to Gregorian year: day-of-year 0-359 = months, 360+ = bonus days.
    function getDecimalDate() as Array {
        var info   = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var gYear  = info.year;
        var gMonth = info.month;
        var gDay   = info.day;

        // Compute 0-based day-of-year
        var monthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
        var isLeap = (gYear % 4 == 0 && gYear % 100 != 0) || (gYear % 400 == 0);
        if (isLeap) { monthDays[1] = 29; }

        var doy = gDay - 1;
        for (var i = 0; i < gMonth - 1; i++) {
            doy += monthDays[i];
        }

        if (doy < 360) {
            var mIdx   = doy / 30;
            var dayInM = doy % 30;
            return [dayInM + 1, mIdx];
        }

        var bonusIdx = doy - 360;
        if (bonusIdx > 4) { bonusIdx = 4; }
        return [bonusIdx, -1];
    }

    function censorString(s as String) as String {
        var result = "";
        var i = 0;
        var len = s.length();
        while (i < len) {
            var ch = s.substring(i, i + 1);
            if (ch.equals("6")) {
                var j = i + 1;
                while (j < len) {
                    var next = s.substring(j, j + 1);
                    if (next.equals(":") || next.equals("/")) {
                        j++;
                    } else {
                        break;
                    }
                }
                if (j < len && s.substring(j, j + 1).equals(((66+1) % 10).toString())) {
                    result += "6";
                    var k = i + 1;
                    while (k < j) {
                        result += s.substring(k, k + 1);
                        k++;
                    }
                    result += "*";
                    i = j + 1;
                } else {
                    result += ch;
                    i++;
                }
            } else {
                result += ch;
                i++;
            }
        }
        return result;
    }

    function isNightMode() as Boolean {
        var enabled = Properties.getValue("NightModeEnabled");
        if (enabled == null || !enabled) {
            return false;
        }

        // חישוב השעה הטטריסטית הנוכחית
        var clockTime = System.getClockTime();
        var totalSec  = clockTime.hour.toDouble() * 3600.0
                      + clockTime.min.toDouble()  * 60.0
                      + clockTime.sec.toDouble();
        var decTotal = totalSec * 248832.0 / 86400.0 - 64886.0;
        if (decTotal < 0) { decTotal += 248832.0; }
        var dHour = (decTotal / 20736.0).toNumber();
        var dMin  = ((decTotal - dHour.toDouble() * 20736.0) / 144.0).toNumber();
        
        // זמנים קבועים (טטריסטיים):
        // כניסה למצב שינה: 7:72:00
        // יציאה ממצב שינה: 0:000:000
        var startHour = 7;
        var startMin = 72;
        var endHour = 0;
        var endMin = 0;

        var nowUnits   = dHour * 20736 + dMin * 144;
        
        // כל שעה טטריסטית = 20736 יחידות, כל דקה טטריסטית = 144 יחידות
        var startUnits = startHour * 20736 + startMin * 144;  // 7:72:00
        var endUnits = endHour * 20736 + endMin * 144;        // 0:000:000

        // מצב השינה חוצה חצות (מ-7:72:00 עד 0:000:000 למחרת)
        // כלומר: אם השעה >= 7:72:00 או < 0:000:000
        // אבל 0:000:000 = 0, אז זה פשוט: אם השעה >= 7:72:00
        return nowUnits >= startUnits;
    }

    function toBase12String(value as Number) as String {
        if (value == 0) {
            return "0";
        }

        var digits = "0123456789AB";
        var num = value;
        var result = "";

        while (num > 0) {
            var digit = num % 12;
            result = digits.substring(digit, digit + 1) + result;
            num = num / 12;
        }

        return result;
    }

    function getBodyBatteryBase12() as String {
        // FR55 does not expose Body Battery in this API level.
        // Fallback to device battery percentage so the night layout still compiles.
        var battery = System.getSystemStats().battery;
        if (battery == null) {
            return "--";
        }

        var scaled = ((battery.toDouble() * 144.0) / 100.0) + 0.5;
        var bodyBatteryBase12 = scaled.toNumber();
        if (bodyBatteryBase12 < 0) {
            bodyBatteryBase12 = 0;
        } else if (bodyBatteryBase12 > 144) {
            bodyBatteryBase12 = 144;
        }

        return toBase12String(bodyBatteryBase12);
    }

    function onUpdate(dc as Dc) as Void {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx = width  / 2;
        var cy = height / 2;

        // --- 1. רקע שחור ---
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // בדיקת מצב לילה
        if (isNightMode()) {
            // ===== מצב לילה - תצוגה מינימלית =====
            
            // --- 2. זמן עשרוני (12 שעות, 144 דקות, 144 שניות) ---
            var clockTime = System.getClockTime();
            var totalSec  = clockTime.hour.toDouble() * 3600.0
                          + clockTime.min.toDouble()  * 60.0
                          + clockTime.sec.toDouble();
            
            var decTotal = totalSec * 248832.0 / 86400.0;
            var offsetDecimal = 64886.0;
            decTotal = decTotal - offsetDecimal;
            
            if (decTotal < 0) {
                decTotal += 248832.0;
            }
            var dHour = (decTotal / 20736.0).toNumber();
            var dMin  = ((decTotal - dHour.toDouble() * 20736.0) / 144.0).toNumber();
            var dSec  = (decTotal - dHour.toDouble() * 20736.0
                                  - dMin.toDouble()  * 144.0).toNumber();

            // --- 3. מחרוזות טקסט ---
            var regularTime = censorString(Lang.format("$1$:$2$", [
                clockTime.hour,
                clockTime.min.format("%02d")
            ]));

            var decTimeStr = censorString(Lang.format("$1$:$2$", [
                dHour,
                dMin.format("%03d")
            ]));

            // --- 4. זוויות מחוגים ---
            var hourAngle = dHour.toDouble() * 30.0 + dMin.toDouble() / 144.0 * 30.0;
            var minAngle  = dMin.toDouble() * 2.5 + dSec.toDouble() / 144.0 * 2.5;

            // --- 5. גיאומטריה ---
            var radius  = (width < height ? width : height) / 2 - 4;
            var hourLen = (radius.toDouble() * 0.5).toNumber();
            var minLen  = (radius.toDouble() * 0.72).toNumber();

            // --- 6. מספרים 0–11 (12 שעות) ---
            var numR    = radius - 14;
            var numbers = ["0","1","2","3","4","5","6","7","8","9","10","11"];
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < 12; i++) {
                var ang = (i * 30.0 - 90.0) * (Math.PI / 180.0);
                var nx  = (cx.toDouble() + numR.toDouble() * Math.cos(ang)).toNumber();
                var ny  = (cy.toDouble() + numR.toDouble() * Math.sin(ang)).toNumber();
                dc.drawText(nx, ny, Graphics.FONT_SMALL, numbers[i],
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }

            var bodyBatteryStr = censorString(getBodyBatteryBase12());

            // --- 7. השעונים עוברים לחלק העליון במצב לילה ---
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 44, Graphics.FONT_LARGE, decTimeStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 18, Graphics.FONT_XTINY, regularTime,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- 8. Body Battery בחלק התחתון, בהמרה לבסיס 12 ---
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 20, cy + 44, 4);
            dc.setPenWidth(2);
            dc.drawLine(cx - 20, cy + 48, cx - 20, cy + 58);
            dc.drawLine(cx - 26, cy + 52, cx - 14, cy + 52);
            dc.drawLine(cx - 20, cy + 58, cx - 25, cy + 66);
            dc.drawLine(cx - 20, cy + 58, cx - 15, cy + 66);
            dc.drawText(cx + 4, cy + 50, Graphics.FONT_SMALL, bodyBatteryStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- 9. מחוגים ---
            // מחוג שעות (לבן, דק יותר)
            var hRad = (hourAngle - 90.0) * (Math.PI / 180.0);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(3);
            dc.drawLine(cx, cy,
                (cx.toDouble() + hourLen.toDouble() * Math.cos(hRad)).toNumber(),
                (cy.toDouble() + hourLen.toDouble() * Math.sin(hRad)).toNumber());

            // מחוג דקות (אדום)
            var mRad = (minAngle - 90.0) * (Math.PI / 180.0);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(cx, cy,
                (cx.toDouble() + minLen.toDouble() * Math.cos(mRad)).toNumber(),
                (cy.toDouble() + minLen.toDouble() * Math.sin(mRad)).toNumber());

            // נקודת מרכז
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, 3);
            
            return;
        }

        // ===== מצב רגיל - תצוגה מלאה =====

        // --- 2. זמן עשרוני (12 שעות, 144 דקות, 144 שניות) ---
        // יממה = 12 × 144 × 144 = 248832 יחידות
        var clockTime = System.getClockTime();
        var totalSec  = clockTime.hour.toDouble() * 3600.0
                      + clockTime.min.toDouble()  * 60.0
                      + clockTime.sec.toDouble();
        
        // decTotal = מספר השניות-העשרוניות שחלפו מחצות
        var decTotal = totalSec * 248832.0 / 86400.0;
        
        // הסטה: כאשר decTotal היה 3:18:86 (64886 יחידות), עכשיו יהיה 0:000:000
        // 3×20736 + 18×144 + 86 = 64886
        var offsetDecimal = 64886.0;
        decTotal = decTotal - offsetDecimal;
        
        // אם התוצאה שלילית, הוסף 248832 (יממה עשרונית שלמה)
        if (decTotal < 0) {
            decTotal += 248832.0;
        }
        var dHour = (decTotal / 20736.0).toNumber();                          // 144×144
        var dMin  = ((decTotal - dHour.toDouble() * 20736.0) / 144.0).toNumber();
        var dSec  = (decTotal - dHour.toDouble() * 20736.0
                              - dMin.toDouble()  * 144.0).toNumber();

        // --- 3. תאריך עשרוני ---
        var dateArr  = getDecimalDate();
        var decDay   = dateArr[0];
        var decMonth = dateArr[1];

        // --- 4. מחרוזות טקסט ---
        var dateStr;
        if (decMonth == -1) {
            var extraNames = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"];
            dateStr = extraNames[decDay];
        } else {
            dateStr = censorString(Lang.format("$1$/$2$", [decDay, decMonth + 1]));
        }

        var regularTime = censorString(Lang.format("$1$:$2$:$3$", [
            clockTime.hour,
            clockTime.min.format("%02d"),
            clockTime.sec.format("%02d")
        ]));

        var decTimeStr = censorString(Lang.format("$1$:$2$:$3$", [
            dHour,
            dMin.format("%03d"),
            dSec.format("%03d")
        ]));

        // --- 5. זוויות מחוגים ---
        // שעות: 360°/12 = 30° לשעה; תרומת דקות: 30°/144
        var hourAngle = dHour.toDouble() * 30.0 + dMin.toDouble() / 144.0 * 30.0;
        // דקות: 360°/144 ≈ 2.5° לדקה; תרומת שניות: 2.5°/144
        var minAngle  = dMin.toDouble() * 2.5 + dSec.toDouble() / 144.0 * 2.5;

        // --- 6. גיאומטריה ---
        var radius  = (width < height ? width : height) / 2 - 4;
        var hourLen = (radius.toDouble() * 0.5).toNumber();
        var minLen  = (radius.toDouble() * 0.72).toNumber();

        // --- 8. מספרים 0–11 (12 שעות) ---
        var numR    = radius - 14;
        var numbers = ["0","1","2","3","4","5","6","7","8","9","10","11"];
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 12; i++) {
            var ang = (i * 30.0 - 90.0) * (Math.PI / 180.0);
            var nx  = (cx.toDouble() + numR.toDouble() * Math.cos(ang)).toNumber();
            var ny  = (cy.toDouble() + numR.toDouble() * Math.sin(ang)).toNumber();
            dc.drawText(nx, ny, Graphics.FONT_XTINY, numbers[i],
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        // --- 12. שעה גרגוריאנית ---
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var timeX = cx;
        var timeY = cy - (radius.toDouble() * 0.60).toNumber();
        dc.drawText(timeX, timeY, Graphics.FONT_XTINY, regularTime,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- 13. תאריך עשרוני — מעל המרכז ---
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (radius.toDouble() * 0.38).toNumber(),
                    Graphics.FONT_SMALL, dateStr, Graphics.TEXT_JUSTIFY_CENTER);

        // --- 14. שעה עשרונית — מתחת למרכז ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (radius.toDouble() * 0.28).toNumber(),
                    Graphics.FONT_SMALL, decTimeStr, Graphics.TEXT_JUSTIFY_CENTER);

        // --- 15. צעדים (שמאל) ודופק (ימין) ---
        var sideY  = cy;
        var sideR  = 26;
        var sideOffset = (radius.toDouble() * 0.42).toNumber();
        var leftX  = cx - sideOffset;
        var rightX = cx + sideOffset;

        // --- עיגול צעדים (שמאל, ירוק) ---
        var actInfo = ActivityMonitor.getInfo();
        var stepsStr = "--";
        if (actInfo != null && actInfo.steps != null) {
            stepsStr = censorString(actInfo.steps.toString());
        }
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(leftX, sideY, sideR);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(leftX - 4, sideY - 18, 3, 6);
        dc.fillRectangle(leftX + 1, sideY - 15, 3, 6);
        dc.drawText(leftX, sideY + 8,
                    Graphics.FONT_XTINY, stepsStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // --- עיגול דופק (ימין, ירוק) ---
        var hrStr = "--";
        var activityInfo = Activity.getActivityInfo();
        if (activityInfo != null && activityInfo.currentHeartRate != null) {
            hrStr = censorString(activityInfo.currentHeartRate.toString());
        }
        dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawCircle(rightX, sideY, sideR);

        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawArc(rightX - 4, sideY - 12, 5, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawArc(rightX + 4, sideY - 12, 5, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(rightX - 8, sideY - 12, rightX, sideY - 4);
        dc.drawLine(rightX + 8, sideY - 12, rightX, sideY - 4);
        dc.drawText(rightX, sideY + 8,
                    Graphics.FONT_XTINY, hrStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // =====================================================
        // מחוגים — מצוירים אחרונים = שכבה קדמית
        // =====================================================

        // --- מחוג שעות (לבן, עבה) ---
        var hRad = (hourAngle - 90.0) * (Math.PI / 180.0);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawLine(cx, cy,
            (cx.toDouble() + hourLen.toDouble() * Math.cos(hRad)).toNumber(),
            (cy.toDouble() + hourLen.toDouble() * Math.sin(hRad)).toNumber());

        // --- מחוג דקות (אדום) ---
        var mRad = (minAngle - 90.0) * (Math.PI / 180.0);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx, cy,
            (cx.toDouble() + minLen.toDouble() * Math.cos(mRad)).toNumber(),
            (cy.toDouble() + minLen.toDouble() * Math.sin(mRad)).toNumber());

        // --- נקודת מרכז — מעל הכל ---
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 5);
    }
}
