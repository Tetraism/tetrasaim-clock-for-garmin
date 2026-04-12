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


    var _timer              as Timer.Timer?;
    var _stepsTimer         as Timer.Timer?;  // טיימר 10 שניות one-shot לסיום מסך צעדים
    var _stepsRefreshTimer  as Timer.Timer?;  // טיימר חד-שנייתי לרענון מסך צעדים
    var _lastSteps          as Number;
    var _showBigSteps       as Boolean;

    function initialize() {
        WatchFace.initialize();
        _timer             = null;
        _stepsTimer        = null;
        _stepsRefreshTimer = null;
        _lastSteps         = -1;
        _showBigSteps      = false;
    }

    // נקרא אחרי 10 שניות — מסיים מסך צעדים
    function onStepsTimeout() as Void {
        _stepsTimer = null;   // הטיימר כבר סיים — אל תקרא stop() עליו
        _showBigSteps = false;
        if (_stepsRefreshTimer != null) {
            (_stepsRefreshTimer as Timer.Timer).stop();
            _stepsRefreshTimer = null;
        }
        WatchUi.requestUpdate();
    }

    // נקרא כל שנייה בזמן מסך הצעדים
    function onStepsRefresh() as Void {
        WatchUi.requestUpdate();
    }

    function onLayout(dc as Dc) as Void {
    }

    function isBatterySaverActive() as Boolean {
        var enabled = Properties.getValue("BatterySaverEnabled");
        if (enabled == null || !enabled) {
            return false;
        }

        var battery = System.getSystemStats().battery;
        return battery != null && battery < 30;
    }

    function shouldShowSeconds() as Boolean {
        return !isBatterySaverActive();
    }

    function startSecondTimer() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
        } else {
            (_timer as Timer.Timer).stop();
        }

        var interval = isBatterySaverActive() ? 30000 : 1000;
        (_timer as Timer.Timer).start(method(:onTick), interval, true);
    }

    function stopSecondTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onShow() as Void {
        // ForceSecondUpdate = true  → טיימר כל שנייה ב-high power
        // ForceSecondUpdate = false → עדכון רק על ידי המערכת (דקה + מחווה + לחיצה)
        var forceSeconds = Properties.getValue("ForceSecondUpdate");
        if (forceSeconds == null || forceSeconds) {
            startSecondTimer();
        }
    }

    function onHide() as Void {
        stopSecondTimer();
    }

    function onEnterSleep() as Void {
        // ב-low power אין טיימרים, ולכן עוצרים אותם.
        stopSecondTimer();
    }

    function onExitSleep() as Void {
        // בחזרה ל-high power מפעילים מחדש טיימר של שנייה.
        var forceSeconds = Properties.getValue("ForceSecondUpdate");
        if (forceSeconds == null || forceSeconds) {
            startSecondTimer();
        }
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onPartialUpdate(dc as Dc) as Void {
        var forceSeconds = Properties.getValue("ForceSecondUpdate");
        if (!(forceSeconds == null || forceSeconds)) {
            return;
        }

        var clockTime = System.getClockTime();

        // במצב שינה מעדכנים רק פעם ב-5 דקות כדי לחסוך סוללה,
        // בלי לשנות את המראה של המסך.
        if (isNightMode()) {
            if ((clockTime.min % 5) != 0 || clockTime.sec != 0) {
                return;
            }
        } else if (isBatterySaverActive()) {
            // במצב חיסכון סוללה מתחת ל-30% מעדכנים רק כל 30 שניות.
            if ((clockTime.sec % 30) != 0) {
                return;
            }
        }

        onUpdate(dc);
    }

    // מחווה (swipe/tap) — מעדכן את המסך כשהטיימר כבוי
    function onGesture(evt as WatchUi.GestureEvent) as Boolean {
        var forceSeconds = Properties.getValue("ForceSecondUpdate");
        if (forceSeconds == null || forceSeconds) {
            return false; // הטיימר / partial update מטפלים בעדכונים
        }
        WatchUi.requestUpdate();
        return true;
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

        var bodyBatteryBase12 = (battery.toDouble() / 100.0 * 144.0).toNumber();

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

        // ===== בדיקת שינוי צעדים → מסך צעדים גדול =====
        var showStepsBig = Properties.getValue("ShowStepsBig");
        if ((showStepsBig == null || showStepsBig) && !isNightMode() && !isBatterySaverActive()) {
            var actInfoCheck = ActivityMonitor.getInfo();
            if (actInfoCheck != null && actInfoCheck.steps != null) {
                var curSteps = actInfoCheck.steps;
                if (_lastSteps >= 0 && curSteps != _lastSteps) {
                    // הצעדים השתנו — מפעילים תצוגה גדולה ומאפסים את הטיימרים
                    _showBigSteps = true;

                    // טיימר 10 שניות — יצירה מחדש תמיד (בטוח יותר מ-stop על טיימר מת)
                    if (_stepsTimer != null) {
                        (_stepsTimer as Timer.Timer).stop();
                    }
                    _stepsTimer = new Timer.Timer();
                    (_stepsTimer as Timer.Timer).start(method(:onStepsTimeout), 10000, false);

                    // טיימר רענון שנייתי — רק אם עוד לא רץ
                    if (_stepsRefreshTimer == null) {
                        _stepsRefreshTimer = new Timer.Timer();
                        (_stepsRefreshTimer as Timer.Timer).start(method(:onStepsRefresh), 1000, true);
                    }
                }
                _lastSteps = curSteps;
            }
        }

        // ===== מסך צעדים גדול =====
        if (_showBigSteps && !isNightMode()) {
            var stepsNow  = ActivityMonitor.getInfo();
            var stepsStr2 = "--";
            var hasGoal   = false;
            var goalPct   = 0.0;
            if (stepsNow != null) {
                if (stepsNow.steps != null) {
                    stepsStr2 = stepsNow.steps.toString();
                }
                if (stepsNow.stepGoal != null && stepsNow.steps != null && stepsNow.stepGoal > 0) {
                    hasGoal = true;
                    goalPct = stepsNow.steps.toDouble() / stepsNow.stepGoal.toDouble();
                    if (goalPct > 1.0) { goalPct = 1.0; }
                }
            }

            // --- חישוב שתי השעות ---
            var sClockTime = System.getClockTime();
            var sTotalSec  = sClockTime.hour.toDouble() * 3600.0
                           + sClockTime.min.toDouble()  * 60.0
                           + sClockTime.sec.toDouble();
            var sDecTotal  = sTotalSec * 248832.0 / 86400.0 - 64886.0;
            if (sDecTotal < 0) { sDecTotal += 248832.0; }
            var sDHour = (sDecTotal / 20736.0).toNumber();
            var sDMin  = ((sDecTotal - sDHour.toDouble() * 20736.0) / 144.0).toNumber();
            var sRegTime = censorString(Lang.format("$1$:$2$", [
                sClockTime.hour, sClockTime.min.format("%02d")]));
            var sDecTime = censorString(Lang.format("$1$:$2$", [sDHour, sDMin.format("%d")]));

            // --- קשת יעד ---
            if (hasGoal) {
                var arcR = width / 2 - 6;
                dc.setPenWidth(4);
                dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(cx, cy, arcR);
                dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
                var arcDeg = (goalPct * 360.0).toNumber();
                if (arcDeg > 0) {
                    dc.drawArc(cx, cy, arcR, Graphics.ARC_COUNTER_CLOCKWISE, 90, 90 - arcDeg);
                }
                dc.setPenWidth(1);
            }

            // --- צעדים במרכז ---
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 5, Graphics.FONT_NUMBER_MEDIUM, stepsStr2,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- /יעד מתחת לצעדים (ירוק, אותו צבע) ---
            if (hasGoal) {
                var stepsNowInfo = ActivityMonitor.getInfo();
                var goalStr = "";
                if (stepsNowInfo != null && stepsNowInfo.stepGoal != null) {
                    goalStr = stepsNowInfo.stepGoal.toString();
                }
                dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy + 28, Graphics.FONT_SMALL,
                            Lang.format("/$1$", [goalStr]),
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }

            // --- שעה טטריסטית בראש ---
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 68, Graphics.FONT_SMALL, sDecTime,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- שעה רגילה מתחתיה ---
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 50, Graphics.FONT_XTINY, sRegTime,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- אחוזי השגת יעד ---
            if (hasGoal) {
                var pctStr = (goalPct * 100.0).toNumber().toString() + "%";
                dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy + 82, Graphics.FONT_XTINY, pctStr,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
            return;
        }

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
                dMin.format("%d")
            ]));

            var bodyBatteryStr = censorString(getBodyBatteryBase12());

            // --- 4. שעה רגילה למעלה (קצת יותר גדולה במצב לילה) ---
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 65, Graphics.FONT_TINY, regularTime,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- 5. שעה טטריסטית במרכז (גדולה מאוד) ---
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 5, Graphics.FONT_NUMBER_HOT, decTimeStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

            // --- 6. Body Battery בתחתית עם סמל קטן בגודל הטקסט ---
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx - 12, cy + 72, 3);
            dc.setPenWidth(1);
            dc.drawLine(cx - 12, cy + 75, cx - 12, cy + 82);
            dc.drawLine(cx - 16, cy + 78, cx - 8, cy + 78);
            dc.drawLine(cx - 12, cy + 82, cx - 16, cy + 87);
            dc.drawLine(cx - 12, cy + 82, cx - 8, cy + 87);
            dc.drawText(cx + 2, cy + 80, Graphics.FONT_TINY, bodyBatteryStr,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            
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

        var regularTime;
        var decTimeStr;
        if (shouldShowSeconds()) {
            regularTime = censorString(Lang.format("$1$:$2$:$3$", [
                clockTime.hour,
                clockTime.min.format("%02d"),
                clockTime.sec.format("%02d")
            ]));

            decTimeStr = censorString(Lang.format("$1$:$2$:$3$", [
                dHour,
                dMin.format("%d"),
                dSec.format("%d")
            ]));
        } else {
            regularTime = censorString(Lang.format("$1$:$2$", [
                clockTime.hour,
                clockTime.min.format("%02d")
            ]));

            decTimeStr = censorString(Lang.format("$1$:$2$", [
                dHour,
                dMin.format("%d")
            ]));
        }

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

        // --- 13. תאריך עשרוני / סוללה — מעל המרכז ---
        if (isBatterySaverActive()) {
            var battPct = System.getSystemStats().battery;
            var battStr = battPct != null ? battPct.toNumber().toString() + "%" : "--";
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (radius.toDouble() * 0.38).toNumber(),
                        Graphics.FONT_SMALL, battStr, Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (radius.toDouble() * 0.38).toNumber(),
                        Graphics.FONT_SMALL, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
        }

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
