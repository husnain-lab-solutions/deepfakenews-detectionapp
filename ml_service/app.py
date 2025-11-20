import os
from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
from typing import Dict
from PIL import Image
import io

USE_HF = os.getenv("USE_HF", "0") not in ("0", "false", "False", "no", "No")

try:
    from transformers import (
        AutoImageProcessor, SiglipForImageClassification,
        DistilBertTokenizerFast, DistilBertForSequenceClassification,
        AutoTokenizer, AutoModelForSequenceClassification, pipeline
    )
    import torch
    HF_AVAILABLE = True and USE_HF
except Exception:
    HF_AVAILABLE = False

app = FastAPI(title="Deepfake ML Service")

class TextPayload(BaseModel):
    text: str

# Lazy-loaded models
_image_model = None
_image_processor = None
_text_model = None
_text_tokenizer = None
_zero_shot = None
_clf_tokenizer = None
_clf_model = None

IMAGE_MODEL_NAME = os.getenv("IMAGE_MODEL", "prithivMLmods/deepfake-detector-model-v1")
TEXT_MODEL_NAME = os.getenv("TEXT_MODEL", "distilbert-base-uncased-finetuned-sst-2-english")
ZERO_SHOT_MODEL = os.getenv("ZERO_SHOT_MODEL", "facebook/bart-large-mnli")
# Allow runtime tuning of zero-shot prompt and candidate labels
ZERO_SHOT_TEMPLATE = os.getenv("ZERO_SHOT_TEMPLATE", "This news is {}.")
ZERO_SHOT_CANDIDATES = [
    c.strip() for c in os.getenv("ZERO_SHOT_CANDIDATES", "fake,real").split(",") if c.strip()
]
TEXT_CLASSIFIER_MODEL = os.getenv("TEXT_CLASSIFIER_MODEL", "hamzab/roberta-fake-news-classification")
TEXT_MODE = os.getenv("TEXT_MODE", "classifier" if TEXT_CLASSIFIER_MODEL else "heuristic")
ALLOW_DOWNLOADS = os.getenv("HF_ALLOW_DOWNLOADS", "0") not in ("0", "false", "False", "no", "No")

# Synonyms to robustly map model labels back to Real/Fake
_FAKE_SYNONYMS = [s.strip().lower() for s in os.getenv(
    "FAKE_SYNONYMS",
    "fake,false,fabricated,hoax,misleading,untrue,deceptive,clickbait"
).split(",") if s.strip()]
_REAL_SYNONYMS = [s.strip().lower() for s in os.getenv(
    "REAL_SYNONYMS",
    "real,true,accurate,verified,authentic,reliable,genuine"
).split(",") if s.strip()]

def _label_to_simple(label: str) -> str:
    l = (label or "").lower()
    if any(w in l for w in _FAKE_SYNONYMS):
        return "Fake"
    if any(w in l for w in _REAL_SYNONYMS):
        return "Real"
    # Default: lean Real when unknown label
    return "Real"

@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "OK"}

@app.get("/")
def root() -> Dict[str, str]:
    return {"status": "OK", "service": "Deepfake ML Service", "hint": "Use /health, /predict-text, or /predict-image"}

def _calibrate_conf(p: float) -> float:
    # Keep confidence within a reasonable band for demo; avoid 1.0 certainty
    return float(min(0.9, max(0.55, p)))

def _claiminess_penalty(text: str) -> float:
    # If text looks claim-heavy (numbers, years, teams, superlatives), slightly reduce confidence
    t = text.lower()
    indicators = [
        any(ch.isdigit() for ch in t),
        any(y in t for y in [" 2019", " 2020", " 2021", " 2022", " 2023", " 2024", " 2025"]),
        any(k in t for k in ["won by", "defeated", "champion", "world cup", "breaking", "exclusive"]),
    ]
    return 0.9 if any(indicators) else 1.0

@app.post("/predict-text")
def predict_text(payload: TextPayload):
    text = payload.text.strip()
    if not text:
        return {"label": "Unknown", "confidence": 0.0}
    # Preferred: dedicated classifier if provided
    if HF_AVAILABLE and TEXT_CLASSIFIER_MODEL and TEXT_MODE in ("classifier", "auto"):
        global _clf_tokenizer, _clf_model
        try:
            if _clf_model is None:
                _clf_tokenizer = AutoTokenizer.from_pretrained(TEXT_CLASSIFIER_MODEL, local_files_only=not ALLOW_DOWNLOADS)
                _clf_model = AutoModelForSequenceClassification.from_pretrained(TEXT_CLASSIFIER_MODEL, local_files_only=not ALLOW_DOWNLOADS)
            inputs = _clf_tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
            with torch.no_grad():
                outputs = _clf_model(**inputs)
                probs = outputs.logits.softmax(dim=-1).squeeze().tolist()
            # Map labels robustly, allowing synonyms
            id2label = getattr(_clf_model.config, "id2label", {}) or {}
            fake_idx = next((i for i, l in id2label.items() if any(w in l.lower() for w in _FAKE_SYNONYMS)), None)
            real_idx = next((i for i, l in id2label.items() if any(w in l.lower() for w in _REAL_SYNONYMS)), None)
            if fake_idx is None or real_idx is None:
                # Fallback to a reasonable default ordering if unknown
                fake_idx = 0 if fake_idx is None else fake_idx
                real_idx = 1 if real_idx is None else real_idx
            label = "Real" if probs[real_idx] >= probs[fake_idx] else "Fake"
            conf = _calibrate_conf(float(max(probs)) * _claiminess_penalty(text))
            return {"label": label, "confidence": conf}
        except Exception:
            # Fall through to other strategies
            pass
    if HF_AVAILABLE:
        # Prefer a zero-shot NLI classifier for fake vs real over a sentiment model
        global _zero_shot
        try:
            if _zero_shot is None:
                # Respect ALLOW_DOWNLOADS to decide using cache-only or allowing downloads
                _zero_shot = pipeline(
                    "zero-shot-classification",
                    model=ZERO_SHOT_MODEL,
                    local_files_only=not ALLOW_DOWNLOADS
                )
            candidate_labels = ZERO_SHOT_CANDIDATES if ZERO_SHOT_CANDIDATES else ["fake", "real"]
            result = _zero_shot(
                text,
                candidate_labels=candidate_labels,
                hypothesis_template=ZERO_SHOT_TEMPLATE
            )
            top_label = result["labels"][0]
            top_score = float(result["scores"][0])
            penalty = _claiminess_penalty(text)
            conf = _calibrate_conf(top_score * penalty)
            # Map back to Real/Fake even if custom labels are supplied
            label = _label_to_simple(top_label)
            return {"label": label, "confidence": conf}
        except Exception:
            # Fallback to lightweight sentiment model if zero-shot isn't available
            global _text_model, _text_tokenizer
            try:
                if _text_model is None:
                    _text_tokenizer = DistilBertTokenizerFast.from_pretrained(TEXT_MODEL_NAME, local_files_only=True)
                    _text_model = DistilBertForSequenceClassification.from_pretrained(TEXT_MODEL_NAME, local_files_only=True)
            except Exception:
                # If models are not cached locally, avoid long downloads -> fallback heuristic
                label = "Fake" if any(w in text.lower() for w in ["shocking", "breaking", "exclusive"]) else "Real"
                return {"label": label, "confidence": 0.6}
            inputs = _text_tokenizer(text, return_tensors="pt")
            with torch.no_grad():
                outputs = _text_model(**inputs)
                probs = outputs.logits.softmax(dim=-1).squeeze().tolist()
            label = "Real" if probs[1] >= probs[0] else "Fake"
            conf = _calibrate_conf(float(max(probs)) * _claiminess_penalty(text))
            return {"label": label, "confidence": conf}
    # Fallback heuristic
    label = "Fake" if any(w in text.lower() for w in ["shocking", "breaking", "exclusive"]) else "Real"
    return {"label": label, "confidence": 0.6}

@app.post("/predict-image")
def predict_image(file: UploadFile = File(...)):
    data = file.file.read()
    try:
        Image.open(io.BytesIO(data)).convert("RGB")
    except Exception:
        return {"label": "Unknown", "confidence": 0.0}

    if HF_AVAILABLE:
        global _image_model, _image_processor
        if _image_model is None:
            _image_processor = AutoImageProcessor.from_pretrained(IMAGE_MODEL_NAME)
            _image_model = SiglipForImageClassification.from_pretrained(IMAGE_MODEL_NAME)
        image = Image.open(io.BytesIO(data)).convert("RGB")
        inputs = _image_processor(images=image, return_tensors="pt")
        with torch.no_grad():
            outputs = _image_model(**inputs)
            probs = outputs.logits.softmax(dim=-1).squeeze().tolist()
        idx = int(probs.index(max(probs)))
        label = _image_model.config.id2label.get(idx, "Unknown")
        conf = float(max(probs))
        # Normalize to Real/Fake if labels differ
        label_simple = "Fake" if "fake" in label.lower() else "Real"
        return {"label": label_simple, "confidence": conf}

    # Fallback: naive heuristic by file size
    conf = 0.55 if len(data) % 2 == 0 else 0.65
    label = "Fake" if len(data) % 2 == 0 else "Real"
    return {"label": label, "confidence": conf}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
