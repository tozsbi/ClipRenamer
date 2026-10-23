# ClipRenamer

**فكرة ومشروع: toz**

> ⚠️ **نسخة مبدئية (Beta).** الفكرة شغّالة، بس للحين في بدايتها.
> التسمية بالذكاء الاصطناعي **تشتغل كويس لو عندك مفتاح Claude (API)**.
> أما الذكاء المجاني اللي يشتغل على جهازك، فيعرف اللعبة صح، لكن وصفه للمقطع **مو أحسن شي**.

برنامج لويندوز يرتّب مقاطع OBS لحاله:

- **ينقل المقاطع** من مجلد OBS لأي مجلد تختاره، مثل iCloud Drive، فترتفع للسحابة.
- **يسمّي المقاطع بالذكاء الاصطناعي** على اللي صار فيها. يشوف صور المقطع ويسمع الفويس، فبدل `Replay 2026-09-07 14-57-40.mp4` يصير الاسم مثلاً `ميمك بارتي - تقليد زورو Open Na Door - 2026-09-07 14-57-40.mp4`.
- **يفصل المسمّى عن غير المسمّى:** المقاطع اللي تسمّت تروح لمجلد لحالها.
- **زر تشغيل وزر حذف** جنب كل مقطع.

![ClipRenamer](docs/screenshot.png)

## المميزات

| | |
|---|---|
| 🔁 نقل تلقائي | يشتغل عند فتح الجهاز وكل 10 دقايق، حتى لو البرنامج مقفل |
| 🛡️ آمن | ما يكتب فوق أي ملف، وما يلمس المقطع اللي OBS لسا يسجّله |
| ✨ تسمية بالذكاء الاصطناعي | Claude (أدق، بفلوس) أو Ollama (مجاني على جهازك) |
| 🎙️ يفهم الفويس | يحوّل الكلام لكتابة على جهازك (whisper) |
| 📁 تختار المجلدات | من وين ياخذ، ووين يحط، ووين تروح المقاطع المسمّاة |
| 🗑️ حذف | لسلة المحذوفات، أو «المحذوفات مؤخراً» في iCloud |

## التشغيل

1. نزّل المشروع (زر **Code** ثم **Download ZIP**) وفكّه في أي مكان.
2. اضغط مرتين على **`ClipRenamer.vbs`**.
3. من صفحة **«النقل»** اختر المجلدات، وبعدها اضغط الزر الكبير **«تشغيل»**.

### التسمية بالذكاء الاصطناعي

- أول مرة، روح لصفحة **«الذكاء الاصطناعي»** واضغط **«نزّل الأدوات»**. ينزّل ffmpeg وwhisper، تقريباً 1.8 جيجا ومرة وحدة بس.
- اختر وش يسمّي:
  - **Claude (موصى فيه):** حط مفتاح API من [console.anthropic.com](https://console.anthropic.com/settings/keys). تقريباً 5 هللات لكل مقطع.
  - **مجاني على جهازك:** ثبّت [Ollama](https://ollama.com) وشغّل `ollama pull qwen3-vl:8b-instruct`. يحتاج كرت شاشة كويس (8 جيجا أو أكثر).

## المتطلبات

- Windows 10 أو 11
- [OBS Studio](https://obsproject.com/)
- ما يحتاج Python، لأنه مكتوب بـ PowerShell، وهو موجود في ويندوز أصلاً.

## الخصوصية

- مفتاح Claude ينحفظ **مشفّر** على جهازك بس.
- الصوت يتحوّل لكتابة **على جهازك**، والصوت نفسه ما يطلع.
- مع Claude بس: يطلع للإنترنت 6 صور من المقطع والكلام المكتوب. ومع Ollama ما يطلع أي شي.

---

## English

**ClipRenamer** is an idea and project by **toz**.

> ⚠️ **Early version (beta).** AI naming works well with a **Claude API key**. The free on-device option (Ollama) gets the game right, but its descriptions are not great yet.

A Windows app (PowerShell + WPF, no installs) that:

- moves OBS clips to any folder you pick (for example iCloud Drive), at logon and every 10 minutes, never overwriting and never touching a clip that is still recording;
- names clips with AI from 6 frames plus a local speech-to-text transcript of the voice chat (Claude API, or free local Ollama + Qwen3-VL);
- keeps named clips in their own folder, with play and delete buttons for each clip.

Start it by double-clicking `ClipRenamer.vbs`. AI naming needs the tools from **Setup-Tools.ps1** (ffmpeg + whisper.cpp, about 1.8 GB).

## License

MIT © toz
