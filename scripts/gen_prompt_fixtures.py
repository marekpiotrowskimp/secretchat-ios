#!/usr/bin/env python3
"""Renders the official Gemma 4 chat template (from the GGUF) into fixtures for PromptBuilder tests."""
import json, pathlib
from jinja2 import Environment

here = pathlib.Path(__file__).resolve().parent.parent / "GemmaKit/Tests/GemmaKitTests/Fixtures"
# 12B template, and the E2B/E4B one (no empty thought channel when thinking is off).
TEMPLATES = {"gemma4_prompts.json": "gemma4_chat_template.jinja", "gemma4_e_prompts.json": "gemma4_e_chat_template.jinja"}

cases = {
    "user_only": dict(messages=[{"role": "user", "content": "Cześć!"}], enable_thinking=False),
    "system_user_thinking": dict(messages=[{"role": "system", "content": "Jesteś pomocny."},
                                           {"role": "user", "content": "Ile to 2+2?"}], enable_thinking=True),
    "multi_turn": dict(messages=[{"role": "system", "content": "Odpowiadaj krótko."},
                                 {"role": "user", "content": "Hej"},
                                 {"role": "assistant", "content": "Cześć! W czym pomóc?"},
                                 {"role": "user", "content": "  Opowiedz żart.  "}], enable_thinking=False),
    "image": dict(messages=[{"role": "user", "content": [{"type": "image"}, {"type": "text", "text": "Co jest na zdjęciu?"}]}],
                  enable_thinking=False),
    "thinking_only_no_system": dict(messages=[{"role": "user", "content": "Pomyśl."}], enable_thinking=True),
}

# Tool calling (web_search) — same declaration the app uses.
WEB_TOOL = [{"type": "function", "function": {
    "name": "web_search",
    "description": "Wyszukuje w internecie aktualne informacje: wiadomości, wyniki sportowe, pogodę, ceny, kursy walut i wydarzenia, które mogły nastąpić po dacie Twojej wiedzy. Zwraca fragmenty stron ze źródłami.",
    "parameters": {"type": "object", "properties": {
        "query": {"type": "string", "description": "Krótkie zapytanie do wyszukiwarki."},
    }, "required": ["query"]},
}}]
cases.update({
    "tools_user": dict(messages=[{"role": "user", "content": "Jaka jest pogoda?"}], tools=WEB_TOOL, enable_thinking=False),
    "tools_system_thinking": dict(messages=[{"role": "system", "content": "Bądź zwięzły."}, {"role": "user", "content": "Kto wygrał?"}],
                                  tools=WEB_TOOL, enable_thinking=True),
    "tools_history": dict(messages=[
        {"role": "user", "content": "Pogoda w Krakowie?"},
        {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": "web_search", "arguments": {"query": "pogoda \"Kraków\" dziś"}}}]},
        {"role": "tool", "name": "web_search", "content": "[1] Słonecznie, 20°C."},
    ], tools=WEB_TOOL, enable_thinking=False),
})
# Memory tools: several string parameters (sorted by name in the template) and a long system prompt.
def fn(name, desc, params, required):
    return {"type": "function", "function": {"name": name, "description": desc, "parameters": {
        "type": "object", "properties": {k: {"type": "string", "description": v} for k, v in params.items()}, "required": required}}}
MEMORY_TOOLS = [
    fn("memory_save", "Zapisuje informację w pamięci długotrwałej użytkownika — zostaje między rozmowami.",
       {"name": "Krótka nazwa wspomnienia (1–4 słowa). Jeśli użytkownik jej nie podał, wymyśl ją.",
        "description": "Jedno zdanie: czego dotyczy wspomnienie i kiedy się przyda.",
        "content": "Pełna treść do zapamiętania."}, ["name", "description", "content"]),
    fn("memory_read", "Wczytuje treść wspomnienia z pamięci długotrwałej.", {"name": "Nazwa wspomnienia z listy."}, ["name"]),
    fn("memory_delete", "Usuwa wspomnienie, gdy użytkownik prosi, żeby o czymś zapomnieć.", {"name": "Nazwa wspomnienia z listy."}, ["name"]),
]
cases["memory_tools"] = dict(messages=[{"role": "system", "content": "Sys."}, {"role": "user", "content": "Zapamiętaj to."}],
                             tools=MEMORY_TOOLS + WEB_TOOL, enable_thinking=False)
for out_name, template_name in TEMPLATES.items():
    tmpl = Environment().from_string((here / template_name).read_text())
    out = {name: tmpl.render(bos_token="<bos>", add_generation_prompt=True, **kw) for name, kw in cases.items()}
    (here / out_name).write_text(json.dumps(out, ensure_ascii=False, indent=2))
    print(out_name, json.dumps(out, ensure_ascii=False, indent=2))
