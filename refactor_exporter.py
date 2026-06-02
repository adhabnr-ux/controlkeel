import re
import os

def to_pascal_case(s):
    return ''.join(word.capitalize() for word in re.split(r'[-_]', s))

def to_snake_case(s):
    return s.replace('-', '_')

content = open('lib/controlkeel/skills/exporter.ex').read()

# We need to find `defp write_target(%SkillTarget{id: "id"}, ...)`
# and extract the body.
blocks = []
pattern = re.compile(r'  defp write_target\(%SkillTarget\{id: "(.*?)"\}, (.*?)\) do\n(.*?)\n  end\n', re.DOTALL)

def replacer(match):
    target_id = match.group(1)
    args = match.group(2)
    body = match.group(3)

    if 'ControlKeel.Skills.Exporter.' in body and 'write(' in body:
        return match.group(0) # Already delegated

    module_name = to_pascal_case(target_id)
    file_name = to_snake_case(target_id) + ".ex"

    print(f"Extracting {target_id} to {file_name} in module {module_name}")

    # We need to add E. to function calls. What function calls are in body?
    # e.g., `write_skill_tree`, `with_common_assets`, `mcp_payload`, `instructions_only_contents`, etc.
    # A simple regex for word followed by '(' or space? It's better to just write it manually or define a list of known functions.
    pass

replacer_stub = pattern.sub(replacer, content)
