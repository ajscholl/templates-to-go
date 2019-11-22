{
{-# LANGUAGE OverloadedStrings #-}
module Text.Template.Parser (parseTemplate, parsePatternDecls, Stmt(..), Expr(..), Pattern(..), PatternDecl(..), PatternType(..)) where

import Control.Monad.Except
import Control.Monad.Reader

import Data.ByteString.Lazy (ByteString)

import Data.Maybe

import Text.Template.Lexer

}

%name parseTemplateP
%partial parsePatternDeclsP PatternDecls
%tokentype { Token }
%error { parseError }
%monad { Either String }
%expect 8

%token
    id          { TId $$ }
    char        { TChar $$ }
    ' '         { TSpaces $$ }
    '('         { TLParen }
    ')'         { TRParen }
    '{{'        { TLBrace2 }
    '}}'        { TRBrace2 }
    '['         { TLBracket }
    ']'         { TRBracket }
    ':'         { TColon }
    ','         { TComma }
    '.'         { TDot }
    '='         { TEqual }
    '_'         { TWild }
    for         { TFor }
    in          { TIn }
    if          { TIf }
    else        { TElse }
    elseIf      { TElseIf }
    endIf       { TEndIf }
    endFor      { TEndFor }
    '\n'        { TNewline }

%%

Template :: { [Stmt] }
        : List(Stmt)                                                { $1 }

PatternDecls :: { [PatternDecl] }
             : ListSepBy(PatternDecl, '\n') Newlines                { $1 }

PatternDecl :: { PatternDecl }
            : Spaces TokenR(id) ':' PatternTypeS                    { PatternDecl $2 $4 }

PatternTypeS :: { PatternType }
             : Spaces PatternType Spaces                            { $2 }

PatternType :: { PatternType }
            : '[' PatternTypeS ']'                                  { ListType $2 }
            | '(' List1SepBy(PatternTypeS, Comma) ')'               { TupleType $2 }
            | id                                                    { namedType $1 }

Stmt :: { Stmt }
       : PrintStmt                                                  { $1 }
       | IfStmt                                                     { $1 }
       | ForStmt                                                    { $1 }
       | VerbatimStmt                                               { $1 }

VerbatimStmt :: { Stmt }
             : id                                                   { VerbatimStmt $1 }
             | char                                                 { VerbatimStmt $1 }
             | ' '                                                  { VerbatimStmt $1 }
             | '('                                                  { VerbatimStmt "(" }
             | ')'                                                  { VerbatimStmt ")" }
             | '['                                                  { VerbatimStmt "[" }
             | ']'                                                  { VerbatimStmt "]" }
             | ':'                                                  { VerbatimStmt ":" }
             | ','                                                  { VerbatimStmt "," }
             | '.'                                                  { VerbatimStmt "." }
             | '='                                                  { VerbatimStmt "=" }
             | '_'                                                  { VerbatimStmt "_" }
             | in                                                   { VerbatimStmt "in" }
             | '\n'                                                 { VerbatimStmt "\n" }

PrintStmt :: { Stmt }
          : '{{' Expr '}}'                                          { PrintStmt $2 }

IfStmt :: { Stmt }
       : Cmd(IfStart) Template ElseIfBlock ElseBlock                { IfStmt $1 $2 $3 $4 }

ElseIfBlock :: { [(Expr, [Stmt])] }
            : Cmd(ElseIf) Template ElseIfBlock                      { ($1, $2) : $3 }
            | Empty                                                 { [] }

ElseBlock :: { [Stmt] }
          : EndCmd(else) Template EndCmd(endIf)                     { $2 }
          | EndCmd(endIf)                                           { [] }

ForStmt :: { Stmt }
        : Cmd(ForStart) Template EndCmd(endFor)                     { ForStmt $1 $2 }

ForStart :: { (Pattern, Expr) }
         : for Pattern Spaces in Expr                               { ($2, $5) }

IfStart :: { Expr }
        : if Expr                                                   { $2 }

ElseIf :: { Expr }
       : elseIf Expr                                                { $2 }

Spaces :: { () }
       : ' '                                                        { () }
       | Empty                                                      { () }

Cmd(t) : t '}}' Newlines                                            { $1 }

EndCmd(t) : t Newlines                                              { $1 }

Expr :: { Expr }
     : List1(ExprContent)                                           { Expr $ mconcat $1 }

ExprContent :: { ByteString }
             : id                                                   { $1 }
             | char                                                 { $1 }
             | ' '                                                  { $1 }
             | '('                                                  { "(" }
             | ')'                                                  { ")" }
             | '['                                                  { "[" }
             | ']'                                                  { "]" }
             | ':'                                                  { ":" }
             | ','                                                  { "," }
             | '.'                                                  { "." }
             | '='                                                  { "=" }
             | '_'                                                  { "_" }
             | '\n'                                                 { "\n" }

Pattern :: { Pattern }
        : ' ' Pattern                                               { $2 }
        | id                                                        { VarP $1 }
        | '_'                                                       { WildP }
        | '(' List1SepBy(Pattern, Comma) ')'                        { TupP $2 }

Comma :: { () }
      : Spaces ','                                                  { () }

TokenR(t) : t Spaces                                                { $1 }

Newlines :: { () }
         : '\n'                                                     { () }
         | Empty                                                    { () }

List(p) : RevList(p)                                                { reverse $1 }

RevList(p) : RevList(p) p                                           { $2 : $1 }
           | Empty                                                  { [] }

List1(p) : RevList1(p)                                              { reverse $1 }

RevList1(p) : RevList1(p) p                                         { $2 : $1 }
            | p                                                     { [$1] }

List1SepBy(p,s) : RevList1SepBy(p,s)                                { reverse $1 }

ListSepBy(p,s) : List1SepBy(p,s)                                    { $1 }
               | Empty                                              { [] }

RevList1SepBy(p,s) : RevList1SepBy(p,s) s p                         { $3 : $1 }
                   | p                                              { [$1] }

Empty :: { () }
      : {- empty -}                                                 { () }

{

--------------
-- * Utilities
--------------

namedType :: ByteString -> PatternType
namedType "String" = StringType
namedType "Number" = NumberType
namedType "Bool"   = BoolType
namedType name     = error $ show name

parseError :: [Token] -> Either String a
parseError []    = Left $ "Parse error at end of input"
parseError xs    = Left $ "Parse error on " <> showTokens xs <> show xs

----------------------
-- * Module definition
----------------------

data Stmt = VerbatimStmt ByteString
          | PrintStmt Expr
          | IfStmt Expr [Stmt] [(Expr, [Stmt])] [Stmt]
          | ForStmt (Pattern, Expr) [Stmt]
          deriving Show

newtype Expr = Expr ByteString deriving Show

data Pattern = VarP ByteString
             | WildP
             | TupP [Pattern]
             deriving Show

data PatternDecl = PatternDecl ByteString PatternType deriving Show

data PatternType = ListType PatternType
                 | TupleType [PatternType]
                 | StringType
                 | NumberType
                 | BoolType
                 deriving Show

-----------------
-- * Entry points
-----------------

-- | Parse a source file into a list of statements
parseTemplate :: ByteString -> Either String [Stmt]
parseTemplate t = lexer t >>= parseTemplateP

parsePatternDecls :: ByteString -> Either String [PatternDecl]
parsePatternDecls t = lexer t >>= parsePatternDeclsP

}