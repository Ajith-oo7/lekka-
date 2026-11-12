// Push message text in the receiver's language.
//
// Telugu and Hindi here were drafted without a native speaker: review them
// together with the app strings (lib/l10n/TRANSLATION_REVIEW.md).
// The Reminders screen in the app builds the same sentences from its own
// language files, so keep the two in step when wording changes.

export type Kind = "due_soon" | "due_today" | "overdue" | "ping";
export type Lang = "en" | "te" | "hi";

export interface Reminder {
  kind: Kind;
  language: string;
  to_lender: boolean; // true: sent to a lender whose borrower has no app
  person_name: string; // the other person on the loan
  balance_paise: number;
  late_paise: number; // late interest added so far
  due_date: string | null; // YYYY-MM-DD
}

/** ₹ with Indian grouping; paise only when not zero. 123456700 → ₹12,34,567 */
export function formatRupees(paise: number): string {
  const abs = Math.abs(Math.round(paise));
  const whole = String(Math.floor(abs / 100));
  const rest = abs % 100;
  let grouped = whole;
  if (whole.length > 3) {
    let head = whole.slice(0, -3);
    const parts: string[] = [];
    while (head.length > 2) {
      parts.unshift(head.slice(-2));
      head = head.slice(0, -2);
    }
    if (head) parts.unshift(head);
    grouped = parts.join(",") + "," + whole.slice(-3);
  }
  return (paise < 0 ? "-" : "") + "₹" + grouped + (rest ? "." + String(rest).padStart(2, "0") : "");
}

const MONTHS: Record<Lang, string[]> = {
  en: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
  te: ["జన", "ఫిబ్ర", "మార్చి", "ఏప్రి", "మే", "జూన్", "జులై", "ఆగ", "సెప్టెం", "అక్టో", "నవం", "డిసెం"],
  hi: ["जन॰", "फ़र॰", "मार्च", "अप्रैल", "मई", "जून", "जुल॰", "अग॰", "सित॰", "अक्टू॰", "नव॰", "दिस॰"],
};

/** 2026-11-04 → 04 Nov 2026 */
export function formatDate(iso: string | null, lang: Lang): string {
  if (!iso) return "";
  const [y, m, d] = iso.split("-");
  return `${d} ${MONTHS[lang][Number(m) - 1]} ${y}`;
}

type Text = { title: string; body: string };
type Vars = { name: string; amount: string; late: string; date: string };
type Template = (v: Vars) => Text;

// [to the borrower, to a solo lender]
const TEXT: Record<Lang, Record<Kind, [Template, Template]>> = {
  en: {
    due_soon: [
      (v) => ({ title: "Payment due in 2 days", body: `Your payment to ${v.name} is due on ${v.date}. Balance: ${v.amount}.` }),
      (v) => ({ title: "Payment due in 2 days", body: `${v.name}'s payment is due on ${v.date}. Balance: ${v.amount}.` }),
    ],
    due_today: [
      (v) => ({ title: "Payment due today", body: `Your payment to ${v.name} is due today. Balance: ${v.amount}.` }),
      (v) => ({ title: "Payment due today", body: `${v.name}'s payment is due today. Balance: ${v.amount}.` }),
    ],
    overdue: [
      (v) => ({ title: "Payment overdue", body: `Your payment to ${v.name} is overdue. Late interest added so far: ${v.late}. Balance: ${v.amount}.` }),
      (v) => ({ title: "Payment overdue", body: `${v.name}'s payment is overdue. Late interest added so far: ${v.late}. Balance: ${v.amount}.` }),
    ],
    ping: [
      (v) => ({ title: `Reminder from ${v.name}`, body: `${v.name} is reminding you about your loan. Balance: ${v.amount}.` }),
      (v) => ({ title: `Reminder from ${v.name}`, body: `${v.name} is reminding you about your loan. Balance: ${v.amount}.` }),
    ],
  },
  te: {
    due_soon: [
      (v) => ({ title: "2 రోజుల్లో చెల్లింపు గడువు", body: `${v.name} కు మీ చెల్లింపు గడువు ${v.date}. బాకీ: ${v.amount}.` }),
      (v) => ({ title: "2 రోజుల్లో చెల్లింపు గడువు", body: `${v.name} చెల్లింపు గడువు ${v.date}. బాకీ: ${v.amount}.` }),
    ],
    due_today: [
      (v) => ({ title: "ఈ రోజు చెల్లింపు గడువు", body: `${v.name} కు మీ చెల్లింపు గడువు ఈ రోజే. బాకీ: ${v.amount}.` }),
      (v) => ({ title: "ఈ రోజు చెల్లింపు గడువు", body: `${v.name} చెల్లింపు గడువు ఈ రోజే. బాకీ: ${v.amount}.` }),
    ],
    overdue: [
      (v) => ({ title: "చెల్లింపు గడువు దాటింది", body: `${v.name} కు మీ చెల్లింపు గడువు దాటింది. ఇప్పటివరకు జోడించిన ఆలస్య వడ్డీ: ${v.late}. బాకీ: ${v.amount}.` }),
      (v) => ({ title: "చెల్లింపు గడువు దాటింది", body: `${v.name} చెల్లింపు గడువు దాటింది. ఇప్పటివరకు జోడించిన ఆలస్య వడ్డీ: ${v.late}. బాకీ: ${v.amount}.` }),
    ],
    ping: [
      (v) => ({ title: `${v.name} నుంచి రిమైండర్`, body: `${v.name} మీ అప్పు గురించి గుర్తు చేస్తున్నారు. బాకీ: ${v.amount}.` }),
      (v) => ({ title: `${v.name} నుంచి రిమైండర్`, body: `${v.name} మీ అప్పు గురించి గుర్తు చేస్తున్నారు. బాకీ: ${v.amount}.` }),
    ],
  },
  hi: {
    due_soon: [
      (v) => ({ title: "2 दिन में भुगतान देय", body: `${v.name} को आपका भुगतान ${v.date} को देय है। बाकी: ${v.amount}।` }),
      (v) => ({ title: "2 दिन में भुगतान देय", body: `${v.name} का भुगतान ${v.date} को देय है। बाकी: ${v.amount}।` }),
    ],
    due_today: [
      (v) => ({ title: "आज भुगतान देय", body: `${v.name} को आपका भुगतान आज देय है। बाकी: ${v.amount}।` }),
      (v) => ({ title: "आज भुगतान देय", body: `${v.name} का भुगतान आज देय है। बाकी: ${v.amount}।` }),
    ],
    overdue: [
      (v) => ({ title: "भुगतान का समय निकल गया", body: `${v.name} को आपके भुगतान का समय निकल गया है। अब तक जोड़ा गया लेट ब्याज: ${v.late}। बाकी: ${v.amount}।` }),
      (v) => ({ title: "भुगतान का समय निकल गया", body: `${v.name} के भुगतान का समय निकल गया है। अब तक जोड़ा गया लेट ब्याज: ${v.late}। बाकी: ${v.amount}।` }),
    ],
    ping: [
      (v) => ({ title: `${v.name} की ओर से रिमाइंडर`, body: `${v.name} आपको आपके कर्ज़ की याद दिला रहे हैं। बाकी: ${v.amount}।` }),
      (v) => ({ title: `${v.name} की ओर से रिमाइंडर`, body: `${v.name} आपको आपके कर्ज़ की याद दिला रहे हैं। बाकी: ${v.amount}।` }),
    ],
  },
};

export function buildMessage(r: Reminder): Text {
  const lang: Lang = r.language === "te" || r.language === "hi" ? r.language : "en";
  const template = TEXT[lang][r.kind][r.to_lender ? 1 : 0];
  return template({
    name: r.person_name || "Lekka",
    amount: formatRupees(r.balance_paise ?? 0),
    late: formatRupees(r.late_paise ?? 0),
    date: formatDate(r.due_date, lang),
  });
}
