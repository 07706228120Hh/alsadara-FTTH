using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Sadara.API.Controllers;

/// <summary>
/// OCR API — استخراج بيانات الهوية العراقية
/// Google Vision API (أساسي) + Tesseract (احتياطي)
/// </summary>
[ApiController]
[Route("api/[controller]")]
[AllowAnonymous]
public class OcrController : ControllerBase
{
    private readonly ILogger<OcrController> _logger;
    private readonly IWebHostEnvironment _env;
    private readonly IConfiguration _config;
    private static readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(30) };

    public OcrController(ILogger<OcrController> logger, IWebHostEnvironment env, IConfiguration config)
    {
        _logger = logger;
        _env = env;
        _config = config;
    }

    /// <summary>
    /// استخراج بيانات الهوية من صورة
    /// POST /api/ocr/id-card
    /// </summary>
    [HttpPost("id-card")]
    [RequestSizeLimit(10 * 1024 * 1024)] // 10MB max
    public async Task<IActionResult> ExtractIdCard(IFormFile image)
    {
        if (image == null || image.Length == 0)
            return BadRequest(new { success = false, error = "لم يتم إرسال صورة" });

        var ext = Path.GetExtension(image.FileName).ToLowerInvariant();
        if (ext != ".jpg" && ext != ".jpeg" && ext != ".png")
            return BadRequest(new { success = false, error = "يجب أن تكون الصورة jpg أو png" });

        try
        {
            // حفظ الصورة مؤقتاً
            var tempDir = Path.Combine(Path.GetTempPath(), "sadara-ocr");
            Directory.CreateDirectory(tempDir);
            var tempFile = Path.Combine(tempDir, $"{Guid.NewGuid()}{ext}");

            await using (var stream = new FileStream(tempFile, FileMode.Create))
            {
                await image.CopyToAsync(stream);
            }

            // Google Vision أولاً → Tesseract احتياطي
            var ocrText = await RunOcr(tempFile, includeEnglishOnly: true);

            try { System.IO.File.Delete(tempFile); } catch { }

            if (string.IsNullOrEmpty(ocrText))
                return Ok(new { success = false, error = "لم يتم التعرف على نص في الصورة", rawText = "" });

            // تحليل النص واستخراج الحقول
            var fields = ParseIraqiIdCard(ocrText);
            fields["rawText"] = ocrText;
            fields["success"] = "true";

            _logger.LogInformation("OCR: استخراج بيانات هوية — {Fields}", JsonSerializer.Serialize(fields));

            return Ok(fields);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OCR error");
            return StatusCode(500, new { success = false, error = $"خطأ في المعالجة: {ex.Message}" });
        }
    }

    /// <summary>
    /// استخراج بيانات الهوية من صورتين (أمامية + خلفية)
    /// POST /api/ocr/id-card-both
    /// </summary>
    [HttpPost("id-card-both")]
    [RequestSizeLimit(20 * 1024 * 1024)] // 20MB max
    public async Task<IActionResult> ExtractIdCardBoth(IFormFile? front, IFormFile? back)
    {
        if ((front == null || front.Length == 0) && (back == null || back.Length == 0))
            return BadRequest(new { success = false, error = "يجب إرسال صورة واحدة على الأقل" });

        try
        {
            var tempDir = Path.Combine(Path.GetTempPath(), "sadara-ocr");
            Directory.CreateDirectory(tempDir);

            var mergedFields = new Dictionary<string, string>();
            var allRawText = new List<string>();

            // معالجة كل صورة
            foreach (var (file, label) in new[] { (front, "front"), (back, "back") })
            {
                if (file == null || file.Length == 0) continue;

                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (ext != ".jpg" && ext != ".jpeg" && ext != ".png") continue;

                var tempFile = Path.Combine(tempDir, $"{Guid.NewGuid()}{ext}");
                await using (var stream = new FileStream(tempFile, FileMode.Create))
                    await file.CopyToAsync(stream);

                // Google Vision أولاً → Tesseract احتياطي
                var ocrText = await RunOcr(tempFile, includeEnglishOnly: label == "back");

                try { System.IO.File.Delete(tempFile); } catch { }

                if (string.IsNullOrEmpty(ocrText?.Trim())) continue;

                allRawText.Add($"[{label}] {ocrText}");
                var fields = ParseIraqiIdCard(ocrText);

                // دمج: الحقل الأول يفوز (الأمامي أولوية) إلا إذا فارغ
                foreach (var kv in fields)
                {
                    if (!mergedFields.ContainsKey(kv.Key) || string.IsNullOrWhiteSpace(mergedFields[kv.Key]))
                        mergedFields[kv.Key] = kv.Value;
                }
            }

            mergedFields["rawText"] = string.Join("\n---\n", allRawText);
            // نجاح إذا استخرجنا أي حقل (غير rawText و success)
            mergedFields["success"] = mergedFields.Count >= 1 ? "true" : "false";

            _logger.LogInformation("OCR-Both: {Fields}", JsonSerializer.Serialize(mergedFields));
            return Ok(mergedFields);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "OCR-Both error");
            return StatusCode(500, new { success = false, error = $"خطأ: {ex.Message}" });
        }
    }

    /// <summary>
    /// استدعاء Tesseract OCR
    /// </summary>
    /// معالجة مسبقة للصورة بـ ImageMagick لتحسين OCR
    /// تحويل لرمادي + تباين + تكبير + إزالة ضوضاء
    private async Task<string> PreprocessImage(string imagePath)
    {
        try
        {
            var outputPath = Path.Combine(Path.GetDirectoryName(imagePath)!, $"{Guid.NewGuid()}_processed.png");
            var psi = new ProcessStartInfo
            {
                FileName = "convert",
                Arguments = $"\"{imagePath}\" -resize 1500x1500> \"{outputPath}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };

            using var process = Process.Start(psi);
            if (process == null) return imagePath;

            await process.WaitForExitAsync();

            if (process.ExitCode == 0 && System.IO.File.Exists(outputPath))
            {
                _logger.LogInformation("ImageMagick: preprocessed → {Output}", outputPath);
                return outputPath;
            }

            _logger.LogWarning("ImageMagick failed (exit {Code}), using original", process.ExitCode);
            return imagePath;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "PreprocessImage failed, using original");
            return imagePath;
        }
    }

    /// Google Vision API — أدق بكثير من Tesseract للنص العربي
    private async Task<string> RunGoogleVision(string imagePath)
    {
        var apiKey = _config["GoogleVision:ApiKey"] ?? Environment.GetEnvironmentVariable("GOOGLE_VISION_API_KEY");
        if (string.IsNullOrEmpty(apiKey))
        {
            _logger.LogWarning("Google Vision API key not configured");
            return "";
        }

        try
        {
            var imageBytes = await System.IO.File.ReadAllBytesAsync(imagePath);
            var base64 = Convert.ToBase64String(imageBytes);

            var requestBody = new
            {
                requests = new[]
                {
                    new
                    {
                        image = new { content = base64 },
                        features = new[] { new { type = "TEXT_DETECTION", maxResults = 1 } }
                    }
                }
            };

            var json = JsonSerializer.Serialize(requestBody);
            var content = new StringContent(json, System.Text.Encoding.UTF8, "application/json");

            var response = await _httpClient.PostAsync(
                $"https://vision.googleapis.com/v1/images:annotate?key={apiKey}", content);

            var respBody = await response.Content.ReadAsStringAsync();

            if (response.IsSuccessStatusCode)
            {
                using var doc = JsonDocument.Parse(respBody);
                var responses = doc.RootElement.GetProperty("responses");
                if (responses.GetArrayLength() > 0)
                {
                    var first = responses[0];
                    if (first.TryGetProperty("textAnnotations", out var annotations) && annotations.GetArrayLength() > 0)
                    {
                        var fullText = annotations[0].GetProperty("description").GetString() ?? "";
                        _logger.LogInformation("GoogleVision: {Len} chars", fullText.Length);
                        return fullText;
                    }
                }
            }

            _logger.LogWarning("GoogleVision failed: {Status} {Body}", response.StatusCode, respBody.Length > 200 ? respBody[..200] : respBody);
            return "";
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "GoogleVision error");
            return "";
        }
    }

    /// OCR شامل — Google Vision أولاً، Tesseract احتياطي
    private async Task<string> RunOcr(string imagePath, bool includeEnglishOnly = false)
    {
        // محاولة 1: Google Vision
        var text = await RunGoogleVision(imagePath);
        if (!string.IsNullOrEmpty(text) && text.Length > 10)
        {
            _logger.LogInformation("OCR via GoogleVision: {Len} chars", text.Length);
            return text;
        }

        // محاولة 2: Tesseract عربي+إنجليزي
        text = await RunTesseract(imagePath, "ara+eng");

        // محاولة 3: Tesseract إنجليزي فقط (لـ MRZ)
        if (includeEnglishOnly)
        {
            var engText = await RunTesseract(imagePath, "eng");
            if (!string.IsNullOrEmpty(engText))
                text += "\n" + engText;
        }

        return text;
    }

    private async Task<string> RunTesseract(string imagePath, string lang = "ara+eng")
    {
        try
        {
            // psm 3 = auto (الأفضل لصور الهوية)
            var bestOutput = "";
            foreach (var psm in new[] { 6, 3 })
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "tesseract",
                    Arguments = $"\"{imagePath}\" stdout -l {lang} --psm {psm}",
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                };

                using var process = Process.Start(psi);
                if (process == null) continue;

                var output = await process.StandardOutput.ReadToEndAsync();
                await process.WaitForExitAsync();

                output = output.Trim();
                _logger.LogInformation("Tesseract psm={Psm}: {Len} chars", psm, output.Length);

                // نأخذ أطول نتيجة (أكثر نص مقروء)
                if (output.Length > bestOutput.Length)
                    bestOutput = output;
            }

            return bestOutput;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Tesseract execution failed");
            return await RunPythonOcr(imagePath);
        }
    }

    /// <summary>
    /// Fallback: Python + pytesseract
    /// </summary>
    private async Task<string> RunPythonOcr(string imagePath)
    {
        try
        {
            var script = $"import pytesseract; from PIL import Image; print(pytesseract.image_to_string(Image.open('{imagePath.Replace("\\", "/")}'), lang='ara+eng'))";
            var psi = new ProcessStartInfo
            {
                FileName = "python3",
                Arguments = $"-c \"{script}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            };

            using var process = Process.Start(psi);
            if (process == null) return "";

            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            return output.Trim();
        }
        catch
        {
            return "";
        }
    }

    /// <summary>
    /// تحليل نص الهوية العراقية — MRZ أولاً ثم النص العربي
    /// </summary>
    private Dictionary<string, string> ParseIraqiIdCard(string text)
    {
        var result = new Dictionary<string, string>();
        text = ConvertArabicDigits(text);

        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                        .Select(l => l.Trim())
                        .Where(l => !string.IsNullOrEmpty(l))
                        .ToList();

        var fullText = string.Join(" ", lines);
        _logger.LogInformation("OCR parsed text: {Text}", fullText);

        // ═══ 1. MRZ (الأكثر دقة) — IDIRQ... في أسفل الوجه الخلفي ═══
        ParseMrz(lines, result);

        // ═══ 2. رقم الهوية: 12 رقم يبدأ بـ 19 أو 20 ═══
        if (!result.ContainsKey("idNumber"))
        {
            var idMatch = Regex.Match(fullText, @"((?:19|20)\d{10})");
            if (idMatch.Success) result["idNumber"] = idMatch.Groups[1].Value;
        }

        // ═══ 3. رقم السجل العائلي: يحتوي L ═══
        if (!result.ContainsKey("familyNumber"))
        {
            var famMatch = Regex.Match(fullText, @"(\d{3,4}[L|l1I]\d{10,20})");
            if (famMatch.Success)
            {
                var fam = famMatch.Groups[1].Value;
                fam = Regex.Replace(fam, @"(?<=\d{3,4})[|l1I](?=\d)", "L");
                result["familyNumber"] = fam;
            }
        }

        // ═══ 4. التواريخ ═══
        var dateMatches = Regex.Matches(fullText, @"(\d{4})[/\-\.](\d{1,2})[/\-\.](\d{1,2})");
        foreach (Match dm in dateMatches)
        {
            var date = $"{dm.Groups[1].Value}-{dm.Groups[2].Value.PadLeft(2, '0')}-{dm.Groups[3].Value.PadLeft(2, '0')}";
            var startIdx = Math.Max(0, dm.Index - 40);
            var len = Math.Min(80, fullText.Length - startIdx);
            var ctx = fullText.Substring(startIdx, len);

            if ((ctx.Contains("الولادة") || ctx.Contains("الميلاد")) && !result.ContainsKey("birthday"))
                result["birthday"] = date;
            else if ((ctx.Contains("الاصدار") || ctx.Contains("الإصدار")) && !ctx.Contains("النفاذ") && !result.ContainsKey("issuedAt"))
                result["issuedAt"] = date;
            else if (!result.ContainsKey("birthday"))
                result["birthday"] = date;
            else if (!result.ContainsKey("issuedAt"))
                result["issuedAt"] = date;
        }

        // ═══ 5. مكان الإصدار ═══
        if (!result.ContainsKey("placeOfIssue"))
        {
            foreach (var pp in new[] { @"(مديرية[^,\n]{3,60})", @"(دائرة[^,\n]{3,50})" })
            {
                var pm = Regex.Match(fullText, pp);
                if (pm.Success) { result["placeOfIssue"] = pm.Groups[1].Value.Trim(); break; }
            }
        }

        // ═══ 6. الأسماء من النص العربي ═══
        ParseArabicNames(lines, result);

        return result;
    }

    /// استخراج بيانات من MRZ (Machine Readable Zone)
    /// السطر 1: IDIRQ + docNum + nationalId
    /// السطر 2: YYMMDD (DOB) + sex + YYMMDD (expiry)
    /// السطر 3: <<NAME<<...
    private void ParseMrz(List<string> lines, Dictionary<string, string> result)
    {
        // نبحث عن سطر يبدأ بـ IDIRQ أو يحتوي عليه
        string? mrzLine1 = null, mrzLine2 = null, mrzLine3 = null;
        for (int i = 0; i < lines.Count; i++)
        {
            var clean = Regex.Replace(lines[i], @"\s", ""); // إزالة المسافات
            if (clean.Contains("IDIRQ"))
            {
                mrzLine1 = clean;
                if (i + 1 < lines.Count) mrzLine2 = Regex.Replace(lines[i + 1], @"\s", "");
                if (i + 2 < lines.Count) mrzLine3 = Regex.Replace(lines[i + 2], @"\s", "");
                break;
            }
        }

        if (mrzLine1 == null) return;
        _logger.LogInformation("MRZ detected: L1={L1} L2={L2} L3={L3}", mrzLine1, mrzLine2, mrzLine3);

        // السطر 1: IDIRQ A63062108 6 198537098623 <<<
        var m1 = Regex.Match(mrzLine1, @"IDIRQ[A-Z]?(\w{8,9})\d((?:19|20)\d{10})");
        if (m1.Success)
            result["idNumber"] = m1.Groups[2].Value;

        // السطر 2: 851026 4 M 321023 7 IRQ
        if (mrzLine2 != null)
        {
            var m2 = Regex.Match(mrzLine2, @"(\d{6})\d([MF])(\d{6})");
            if (m2.Success)
            {
                // تاريخ الميلاد YYMMDD
                var dob = m2.Groups[1].Value;
                var yy = int.Parse(dob[..2]);
                var century = yy > 50 ? "19" : "20";
                result["birthday"] = $"{century}{dob[..2]}-{dob[2..4]}-{dob[4..6]}";

                // تاريخ الإصدار من الانتهاء - 10 سنوات
                var exp = m2.Groups[3].Value;
                var eyy = int.Parse(exp[..2]);
                var ecentury = eyy > 50 ? "19" : "20";
                var expiryYear = int.Parse($"{ecentury}{exp[..2]}");
                result["issuedAt"] = $"{expiryYear - 10}-{exp[2..4]}-{exp[4..6]}";
            }
        }

        // السطر 3: <<XHYDR<<... → اسم
        if (mrzLine3 != null)
        {
            var namepart = mrzLine3.Replace("<", " ").Trim();
            namepart = Regex.Replace(namepart, @"\s+", " ").Trim();
            // MRZ يحتوي اسم لاتيني مختصر — نحفظه كـ hint فقط
            if (namepart.Length >= 2)
                _logger.LogInformation("MRZ name hint: {Name}", namepart);
        }
    }

    /// استخراج الأسماء من النص العربي
    private void ParseArabicNames(List<string> lines, Dictionary<string, string> result)
    {
        // كلمات مفتاحية ← حقل
        var keywords = new (string[] keys, string field, bool skipIfMother)[]
        {
            (new[] { "الاسم", "الأسم" }, "firstName", false),
            (new[] { "الاب", "الأب" }, "fatherName", false),
            (new[] { "الجد" }, "grandFatherName", true),  // تخطي إذا السطر فيه "الام"
            (new[] { "اللقب", "نازناو" }, "familyName", false),
            (new[] { "الام", "الأم" }, "motherName", false),
        };

        foreach (var line in lines)
        {
            foreach (var (keys, field, skipIfMother) in keywords)
            {
                if (result.ContainsKey(field)) continue;
                if (skipIfMother && (line.Contains("الام") || line.Contains("الأم"))) continue;

                foreach (var kw in keys)
                {
                    if (!line.Contains(kw)) continue;

                    // استخراج القيمة بعد : أو بعد الكلمة
                    string? value = null;
                    if (line.Contains(':'))
                    {
                        value = line.Split(':').Last().Trim();
                    }
                    else
                    {
                        var idx = line.IndexOf(kw) + kw.Length;
                        if (idx < line.Length)
                            value = line[idx..].Trim().TrimStart(':', '-', '/', ' ');
                    }

                    // تنظيف: إزالة الكلمات الكردية بعد /
                    if (value != null && value.Contains('/'))
                        value = value.Split('/')[0].Trim();

                    if (!string.IsNullOrWhiteSpace(value) && value.Length >= 2)
                    {
                        result[field] = value;
                        break;
                    }
                }
            }
        }
    }

    /// تحويل الأرقام العربية/فارسية إلى إنجليزية
    private static string ConvertArabicDigits(string input)
    {
        var sb = new System.Text.StringBuilder(input.Length);
        foreach (var c in input)
        {
            sb.Append(c switch
            {
                '٠' or '۰' => '0', '١' or '۱' => '1', '٢' or '۲' => '2',
                '٣' or '۳' => '3', '٤' or '۴' => '4', '٥' or '۵' => '5',
                '٦' or '۶' => '6', '٧' or '۷' => '7', '٨' or '۸' => '8',
                '٩' or '۹' => '9', _ => c,
            });
        }
        return sb.ToString();
    }
}
