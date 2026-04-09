import Toybox.WatchUi;
import Toybox.Graphics;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Timer;

class decimal_clock_for_garminView extends WatchUi.WatchFace {

    var MONTH_NAMES = [
        "I","II","III","IV","V","VI",
        "VII","VIII","IX","X","XI","XII"
    ];

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

    function getAbsoluteDays(d as Number, m as Number, y as Number) as Number {
        var year  = y;
        var month = m;
        if (month <= 2) {
            year--;
            month += 12;
        }
        return (365.25 * (year + 4716)).toNumber()
             + (30.6001 * (month + 1)).toNumber()
             + d - 1524;
    }

    function isDecimalLeap(decYear as Number) as Boolean {
        var gYear = decYear - 10000;
        return (gYear % 4 == 0 && gYear % 100 != 0) || (gYear % 400 == 0);
    }

    function getDecimalDate() as Array {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        var gDay   = info.day;
        var gMonth = info.month;
        var gYear  = info.year;

        var todayAbs = getAbsoluteDays(gDay, gMonth, gYear);
        var syncAbs  = getAbsoluteDays(1, 1, 0);
        var remaining = todayAbs - syncAbs;

        var decYear = 10000;
        if (remaining >= 0) {
            var running = true;
            while (running) {
                var daysInYear = isDecimalLeap(decYear) ? 366 : 365;
                if (remaining >= daysInYear) {
                    remaining -= daysInYear;
                    decYear++;
                } else {
                    running = false;
                }
            }
        } else {
            var running2 = true;
            while (running2) {
                decYear--;
                var daysInYear2 = isDecimalLeap(decYear) ? 366 : 365;
                remaining += daysInYear2;
                if (remaining >= 0) {
                    running2 = false;
                }
            }
        }

        if (remaining < 360) {
            var mIdx = remaining / 30;
            var d    = (remaining % 30) + 1;
            return [d, mIdx];
        }
        var extraIdx = remaining - 360;
        return [extraIdx, -1];
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

    function onUpdate(dc as Dc) as Void {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx = width  / 2;
        var cy = height / 2;

        // --- 1. רקע שחור ---
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // --- 2. זמן עשרוני (12 שעות, 144 דקות, 144 שניות) ---
        // יממה = 12 × 144 × 144 = 248832 יחידות
        var clockTime = System.getClockTime();
        var totalSec  = clockTime.hour.toDouble() * 3600.0
                      + clockTime.min.toDouble()  * 60.0
                      + clockTime.sec.toDouble();
        // decTotal = מספר השניות-העשרוניות שחלפו מתחילת היום
        var decTotal = totalSec * 248832.0 / 86400.0;
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
            var extraNames = ["a", "b", "c", "d", "e", "Tld"];
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
