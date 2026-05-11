#!/usr/bin/env python3
"""Lint exercises.json and recipes.json for M8 requirements."""

import json
import sys
import os
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
RESOURCES = REPO_ROOT / "LEO" / "Resources" / "Fitness"

VALID_MUSCLE_GROUPS = {
    "chest", "back", "shoulders", "biceps", "triceps", "forearms",
    "quads", "hamstrings", "glutes", "calves", "core", "fullBody", "cardio"
}
VALID_EQUIPMENT = {
    "bodyweight", "dumbbells", "barbell", "machine", "cable", "band", "kettlebell", "pullUpBar"
}
VALID_DIFFICULTY = {"beginner", "intermediate", "advanced"}
VALID_DIET_TAGS = {
    "omnivore", "vegetarian", "vegan", "pescatarian", "keto",
    "paleo", "mediterranean", "halal", "kosher", "custom"
}
VALID_MEAL_TAGS = {"breakfast", "lunch", "dinner", "snack", "preworkout", "postworkout"}

errors = []

def err(msg):
    errors.append(msg)

def validate_exercises():
    path = RESOURCES / "exercises.json"
    if not path.exists():
        err(f"MISSING: {path}")
        return
    exercises = json.loads(path.read_text())
    if not isinstance(exercises, list):
        err("exercises.json: root must be an array")
        return

    ids = set()
    for i, ex in enumerate(exercises):
        prefix = f"exercises[{i}] id={ex.get('id','?')}"

        # Required fields
        for field in ["id", "name", "muscleGroups", "equipment", "metValue",
                      "defaultSets", "defaultReps", "difficulty", "instructions", "videoSearchQuery"]:
            if field not in ex:
                err(f"{prefix}: missing field '{field}'")

        # Unique IDs
        eid = ex.get("id")
        if eid in ids:
            err(f"{prefix}: duplicate id '{eid}'")
        ids.add(eid)

        # MET range
        met = ex.get("metValue", 0)
        if not (1 <= met <= 15):
            err(f"{prefix}: metValue {met} outside 1–15 range")

        # Enum values
        for mg in ex.get("muscleGroups", []):
            if mg not in VALID_MUSCLE_GROUPS:
                err(f"{prefix}: unknown muscleGroup '{mg}'")
        for eq in ex.get("equipment", []):
            if eq not in VALID_EQUIPMENT:
                err(f"{prefix}: unknown equipment '{eq}'")
        diff = ex.get("difficulty")
        if diff and diff not in VALID_DIFFICULTY:
            err(f"{prefix}: unknown difficulty '{diff}'")

    print(f"exercises.json: {len(exercises)} entries, {len(ids)} unique IDs")


def validate_recipes():
    path = RESOURCES / "recipes.json"
    if not path.exists():
        err(f"MISSING: {path}")
        return
    recipes = json.loads(path.read_text())
    if not isinstance(recipes, list):
        err("recipes.json: root must be an array")
        return

    ids = set()
    for i, r in enumerate(recipes):
        prefix = f"recipes[{i}] id={r.get('id','?')}"

        for field in ["id", "name", "dietTags", "allergens", "kcalPerServing",
                      "macros", "ingredients", "instructions", "prepMin", "tags"]:
            if field not in r:
                err(f"{prefix}: missing field '{field}'")

        rid = r.get("id")
        if rid in ids:
            err(f"{prefix}: duplicate id '{rid}'")
        ids.add(rid)

        # 4-4-9 macro/kcal sanity (within 5% of stated kcal)
        macros = r.get("macros", {})
        protein = macros.get("proteinG", 0)
        carb = macros.get("carbG", 0)
        fat = macros.get("fatG", 0)
        computed_kcal = protein * 4 + carb * 4 + fat * 9
        stated_kcal = r.get("kcalPerServing", 0)
        if stated_kcal > 0:
            diff_pct = abs(computed_kcal - stated_kcal) / stated_kcal
            if diff_pct > 0.05:
                err(f"{prefix}: macro kcal {computed_kcal:.0f} vs stated {stated_kcal} exceeds 5% tolerance ({diff_pct*100:.1f}%)")

        # Enum values
        for dt in r.get("dietTags", []):
            if dt not in VALID_DIET_TAGS:
                err(f"{prefix}: unknown dietTag '{dt}'")
        for t in r.get("tags", []):
            if t not in VALID_MEAL_TAGS:
                err(f"{prefix}: unknown mealTag '{t}'")

    print(f"recipes.json: {len(recipes)} entries, {len(ids)} unique IDs")


if __name__ == "__main__":
    validate_exercises()
    validate_recipes()

    if errors:
        print(f"\n{len(errors)} error(s) found:")
        for e in errors:
            print(f"  ERROR: {e}")
        sys.exit(1)
    else:
        print("\nAll checks passed.")
