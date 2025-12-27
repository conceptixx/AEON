# -*- coding: utf-8 -*-
"""
AEON Parser API - Generelle Parser-Schnittstelle

Bietet einheitliche API für alle Dateiformate (JSON, YAML, TOML, etc.)

sys.path requirements: '/path/to/aeon' must be in sys.path
Import: from library.python.parser.parser_api import ParserAPI, ParserFactory
"""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict


class ParseError(Exception):
    """Fehler beim Parsen einer Datei"""
    pass


class ParserAPI(ABC):
    """
    Abstract Base Class für alle Parser.
    
    Jeder Parser (JSON, YAML, TOML) muss diese Interface implementieren.
    Dies ermöglicht einheitlichen Zugriff auf verschiedene Dateiformate.
    """
    
    @abstractmethod
    def load(self, file_path: str) -> Dict[str, Any]:
        """
        Lade und parse eine Datei.
        
        :param file_path: Pfad zur Datei
        :return: Geparste Daten als Dictionary
        :raises FileNotFoundError: Datei existiert nicht
        :raises ParseError: Datei kann nicht geparst werden
        """
        pass
    
    @abstractmethod
    def dump(self, data: Dict[str, Any], file_path: str) -> None:
        """
        Schreibe Daten in eine Datei.
        
        :param data: Zu schreibende Daten
        :param file_path: Ziel-Dateipfad
        :raises IOError: Schreiben fehlgeschlagen
        """
        pass
    
    @abstractmethod
    def dumps(self, data: Dict[str, Any]) -> str:
        """
        Konvertiere Daten zu String.
        
        :param data: Zu konvertierende Daten
        :return: String-Repräsentation
        """
        pass
    
    @abstractmethod
    def loads(self, content: str) -> Dict[str, Any]:
        """
        Parse String zu Daten.
        
        :param content: Zu parsender String
        :return: Geparste Daten
        :raises ParseError: String kann nicht geparst werden
        """
        pass
    
    @staticmethod
    def get_supported_extensions():
        """
        Gibt Liste unterstützter Datei-Endungen zurück.
        
        :return: Liste von Extensions (z.B. ['.json'])
        """
        return []


class ParserFactory:
    """
    Factory zum automatischen Auswählen des richtigen Parsers
    basierend auf Datei-Extension.
    
    Usage:
        # Auto-detect parser
        data = ParserFactory.load("config.json")
        
        # Or get specific parser
        parser = ParserFactory.get_parser("config.toml")
        data = parser.load("config.toml")
    """
    
    _parsers: Dict[str, type] = {}
    _initialized: bool = False
    
    @classmethod
    def _ensure_initialized(cls):
        """
        Stelle sicher, dass Standard-Parser registriert sind.
        
        Wird automatisch aufgerufen bei erstem Zugriff.
        Lazy initialization pattern - verhindert zirkuläre Imports.
        """
        if cls._initialized:
            return
        
        cls._initialized = True
        
        # Registriere Standard-Parser
        try:
            from library.python.parser.json.parser_json import JSONParser
            cls.register('.json', JSONParser)
        except ImportError:
            pass  # JSON Parser optional
        
        # Weitere Parser können hier hinzugefügt werden:
        # try:
        #     from library.python.parser.yaml.parser_yaml import YAMLParser
        #     cls.register('.yaml', YAMLParser)
        #     cls.register('.yml', YAMLParser)
        # except ImportError:
        #     pass
    
    @classmethod
    def register(cls, extension: str, parser_class: type):
        """
        Registriere einen Parser für eine Extension.
        
        :param extension: Datei-Extension (z.B. '.json')
        :param parser_class: Parser-Klasse
        """
        cls._parsers[extension.lower()] = parser_class
    
    @classmethod
    def get_parser(cls, file_path: str) -> ParserAPI:
        """
        Hole passenden Parser für Datei.
        
        :param file_path: Pfad zur Datei
        :return: Parser-Instanz
        :raises ValueError: Kein Parser für Extension registriert
        """
        cls._ensure_initialized()
        
        ext = Path(file_path).suffix.lower()
        
        if ext not in cls._parsers:
            supported = ', '.join(cls._parsers.keys())
            raise ValueError(
                f"No parser registered for extension '{ext}'. "
                f"Supported: {supported}"
            )
        
        parser_class = cls._parsers[ext]
        return parser_class()
    
    @classmethod
    def load(cls, file_path: str) -> Dict[str, Any]:
        """
        Convenience: Auto-detect und load.
        
        :param file_path: Pfad zur Datei
        :return: Geparste Daten
        """
        parser = cls.get_parser(file_path)
        return parser.load(file_path)
    
    @classmethod
    def dump(cls, data: Dict[str, Any], file_path: str) -> None:
        """
        Convenience: Auto-detect und dump.
        
        :param data: Zu schreibende Daten
        :param file_path: Ziel-Dateipfad
        """
        parser = cls.get_parser(file_path)
        parser.dump(data, file_path)
