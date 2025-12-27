# -*- coding: utf-8 -*-
"""
JSON Parser Implementation

Implementiert ParserAPI für JSON Dateien.

sys.path requirements: '/path/to/aeon' must be in sys.path
Import: from library.python.parser.json.parser_json import JSONParser
"""

import json
from typing import Any, Dict

from library.python.parser.parser_api import ParserAPI, ParseError


class JSONParser(ParserAPI):
    """
    JSON Parser Implementation.
    
    Unterstützt .json Dateien mit Standard-JSON Format.
    """
    
    @staticmethod
    def get_supported_extensions():
        """Unterstützte Extensions"""
        return ['.json']
    
    def load(self, file_path: str) -> Dict[str, Any]:
        """
        Lade JSON Datei.
        
        :param file_path: Pfad zur .json Datei
        :return: Geparste Daten
        :raises FileNotFoundError: Datei existiert nicht
        :raises ParseError: JSON ungültig
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except FileNotFoundError:
            raise FileNotFoundError(f"JSON file not found: {file_path}")
        except json.JSONDecodeError as e:
            raise ParseError(f"Invalid JSON in {file_path}: {e}")
    
    def dump(self, data: Dict[str, Any], file_path: str) -> None:
        """
        Schreibe JSON Datei.
        
        :param data: Zu schreibende Daten
        :param file_path: Ziel-Dateipfad
        """
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
    
    def dumps(self, data: Dict[str, Any]) -> str:
        """
        Konvertiere zu JSON String.
        
        :param data: Zu konvertierende Daten
        :return: JSON String
        """
        return json.dumps(data, indent=2, ensure_ascii=False)
    
    def loads(self, content: str) -> Dict[str, Any]:
        """
        Parse JSON String.
        
        :param content: JSON String
        :return: Geparste Daten
        :raises ParseError: JSON ungültig
        """
        try:
            return json.loads(content)
        except json.JSONDecodeError as e:
            raise ParseError(f"Invalid JSON: {e}")


# Auto-register beim Import
from library.python.parser.parser_api import ParserFactory
ParserFactory.register('.json', JSONParser)