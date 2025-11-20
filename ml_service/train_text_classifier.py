import argparse
import os
from typing import Dict

from datasets import load_dataset, Dataset, DatasetDict
import numpy as np
import evaluate
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    DataCollatorWithPadding,
    TrainingArguments,
    Trainer,
)

FAKE_SET = {"pants-fire", "false", "barely-true", "fake"}
REAL_SET = {"half-true", "mostly-true", "true", "real"}
LIAR_INT_TO_NAME = {
    0: "pants-fire",
    1: "false",
    2: "barely-true",
    3: "half-true",
    4: "mostly-true",
    5: "true",
}


def map_liar_labels(example: Dict[str, str]):
    """Map LIAR 6-class labels to binary 0/1 where 1=Real, 0=Fake.
    Accepts either string labels or integer class ids.
    """
    raw = example.get("label", example.get("gold_label", ""))
    if isinstance(raw, int):
        lbl = LIAR_INT_TO_NAME.get(raw, "").lower()
    else:
        lbl = (str(raw) or "").strip().lower()
    if lbl in REAL_SET:
        return {"labels": 1}
    if lbl in FAKE_SET:
        return {"labels": 0}
    # Unknown -> mark as fake to be conservative
    return {"labels": 0}


def build_sample_dataset(text_col: str = "statement") -> DatasetDict:
    """Build a tiny in-repo dataset to allow training without external downloads."""
    samples = [
        ("The government approved a new education budget.", "true"),
        ("NASA confirms water found on Mars in 2020.", "true"),
        ("The vaccine contains microchips to track people.", "false"),
        ("5G towers cause COVID-19 symptoms.", "false"),
        ("Local council launches free community health program.", "true"),
        ("Drinking bleach cures viral infections.", "false"),
        ("The unemployment rate decreased this quarter.", "true"),
        ("Celebrity endorses miracle cure for cancer.", "false"),
        ("A new tax credit supports small businesses.", "true"),
        ("Eating chocolate daily results in 50% weight loss.", "false"),
        ("City introduces electric buses to reduce emissions.", "true"),
        ("Climate change was invented as a hoax.", "false"),
    ]
    data = {
        text_col: [s[0] for s in samples],
        "label": [s[1] for s in samples],
    }
    full = Dataset.from_dict(data)
    split = full.train_test_split(test_size=0.4, seed=42)
    val_test = split["test"].train_test_split(test_size=0.5, seed=42)
    return DatasetDict(train=split["train"], validation=val_test["train"], test=val_test["test"])


def main():
    ap = argparse.ArgumentParser(description="Fine-tune a text classifier for fake/real news")
    ap.add_argument("--model", default="distilbert-base-uncased", help="Base HF model to fine-tune")
    ap.add_argument("--dataset", default="liar", choices=["liar","sample"], help="Dataset to use ('sample' = tiny built-in demo set)")
    ap.add_argument("--text-column", default="statement", help="Text column name in the dataset")
    ap.add_argument("--output-dir", default="models/text-fakenews", help="Where to save the fine-tuned model")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--batch-size", type=int, default=16)
    ap.add_argument("--lr", type=float, default=5e-5)
    args = ap.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    # Load dataset
    if args.dataset == "liar":
        try:
            ds = load_dataset("liar", trust_remote_code=True)  # splits: train/validation/test
        except Exception as e:
            print(f"Warning: failed to load 'liar' dataset ({e}). Falling back to a small built-in sample dataset.")
            ds = build_sample_dataset(args.text_column)
        label_map = map_liar_labels
        text_col = args.text_column
    elif args.dataset == "sample":
        ds = build_sample_dataset(args.text_column)
        label_map = map_liar_labels  # still works (labels are liar-style strings)
        text_col = args.text_column
    else:
        raise ValueError("Unsupported dataset")

    # Prepare tokenizer and model
    tokenizer = AutoTokenizer.from_pretrained(args.model)
    model = AutoModelForSequenceClassification.from_pretrained(args.model, num_labels=2)

    def tokenize(examples):
        return tokenizer(examples[text_col], truncation=True, max_length=256)

    def with_labels(examples):
        mapped = [label_map({"label": l}) for l in examples["label"]]
        return {"labels": [m["labels"] for m in mapped]}

    ds_tok = ds.map(tokenize, batched=True)
    # Add binary labels
    ds_tok = ds_tok.map(lambda e: with_labels(e), batched=True)
    # Keep only model inputs and labels to avoid Trainer using wrong columns
    for split in [s for s in ["train", "validation", "test"] if s in ds_tok]:
        keep = ["input_ids", "attention_mask", "labels"]
        remove_cols = [c for c in ds_tok[split].column_names if c not in keep]
        if remove_cols:
            ds_tok[split] = ds_tok[split].remove_columns(remove_cols)

    data_collator = DataCollatorWithPadding(tokenizer=tokenizer)
    metric_acc = evaluate.load("accuracy")
    metric_f1 = evaluate.load("f1")

    def compute_metrics(eval_pred):
        logits, labels = eval_pred
        preds = np.argmax(logits, axis=-1)
        return {
            "accuracy": metric_acc.compute(predictions=preds, references=labels)["accuracy"],
            "f1": metric_f1.compute(predictions=preds, references=labels, average="weighted")["f1"],
        }

    args_tr = TrainingArguments(
        output_dir=os.path.join(args.output_dir, "runs"),
        evaluation_strategy="epoch",
        save_strategy="epoch",
        learning_rate=args.lr,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        num_train_epochs=args.epochs,
        weight_decay=0.01,
        load_best_model_at_end=True,
        metric_for_best_model="f1",
        logging_steps=50,
        report_to="none",
    )

    trainer = Trainer(
        model=model,
        args=args_tr,
        train_dataset=ds_tok["train"],
        eval_dataset=ds_tok.get("validation", ds_tok.get("test")),
        tokenizer=tokenizer,
        data_collator=data_collator,
        compute_metrics=compute_metrics,
    )

    trainer.train()

    # Save in a form that AutoModel can load later (local path)
    model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)
    print(f"Saved fine-tuned model to {args.output_dir}")


if __name__ == "__main__":
    main()
