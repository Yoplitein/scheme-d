// Inspired by lis.py
// (c) Peter Norvig, 2010; See http://norvig.com/lispy.html
module schemed.eval;

import std.string;
import std.variant;

import schemed.types;
import schemed.environment;
import schemed.parser;


/// Execute a string of code.
/// Returns: Text representation of the result expression.
string execute(string code, Environment env)
{
    Atom result = eval(parseExpression(code), env);
    return toString(result);
}

/// Evaluates an expression.
/// Returns: Result of evaluation.
Atom eval(Atom atom, Environment env)
{
    Atom evalFailure(Atom x0)
    {
        throw new SchemeException(format("%s is not a function", toString(x0)));
    }

    Atom result = atom.visit!(
        (Symbol sym) => env.findSymbol(sym),
        (string s) => atom,
        (double x) => atom,
        (bool b) => atom,
        (Closure fun) => evalFailure(atom),
        (Atom[] atoms)
        {
            // empty list evaluate to itself
            if (atoms.length == 0)
                return atom;

            Atom x0 = atoms[0];

            return x0.visit!(
                (Symbol sym)
                {
                    switch(cast(string)sym)
                    {
                        // Special forms
                        case "quote": 
                            if (atoms.length != 2)
                                throw new SchemeException("Invalid quote expression, should be (quote expr)");
                            return Atom(atoms[1]);

                        case "if":
                            if (atoms.length != 3 && atoms.length != 4)
                                throw new SchemeException("Invalid if expression, should be (if test-expr then-expr [else-expr])");
                            if (toBool(eval(atoms[1], env)))
                                return eval(atoms[2], env);
                            else
                            {
                                if (atoms.length == 4)
                                    return eval(atoms[3], env);
                                else
                                    return makeNil();
                            }

                        case "set!":
                            if (atoms.length != 3)
                                throw new SchemeException("Invalid set! expression, should be (set! var exp)");
                            env.findSymbol(atoms[1].toSymbol) = eval(atoms[2], env);
                            return makeNil();

                        case "define":
                            if (atoms.length != 3)
                                throw new SchemeException("Invalid define expression, should be (define var exp) or (define (fun args...) body)");
                            if (atoms[1].isSymbol)
                                env.values[cast(string)(toSymbol(atoms[1]))] = eval(atoms[2], env);
                            else if (atoms[1].isList)
                            {
                                Atom[] args = toList(atoms[1]);
                                Symbol fun = args[0].toSymbol();
                                env.values[cast(string)(fun)] = Atom(new Closure(env, Atom(args[1..$]), atoms[2]));
                            }
                            else
                                throw new SchemeException("Invalid define expression, should be (define var exp) or (define (fun args...) body)");
                            return makeNil();

                        case "lambda":
                            if (atoms.length != 3)
                                throw new SchemeException("Invalid lambda expression, should be (lambda params body)");
                            return Atom(new Closure(env, atoms[1], atoms[2]));

                        case "begin":
                            if (atoms.length == 3)
                                return atom;
                            Atom lastValue;
                            foreach(ref Atom x; atoms[1..$])
                                lastValue = eval(x, env);
                            return lastValue;

                        // Must be a special form to enable shortcut evaluation
                        case "and":
                        case "or":
                            bool isAnd = sym == "and";
                            Atom lastValue = Atom(isAnd);
                            foreach(arg; atoms[1..$])
                            {
                                lastValue = eval(arg, env);
                                bool b = lastValue.toBool();
                                if (b ^ isAnd)
                                    break;
                            }
                            return lastValue;

                        default:
                            // function call
                            Atom[] values;
                            foreach(ref Atom x; atoms[1..$])
                                values ~= eval(x, env);
                            return apply(eval(atoms[0], env), values);
                    }
                },
                (bool b) => evalFailure(x0),
                (string s) => evalFailure(x0),
                (double x) => evalFailure(x0),
                (Atom[] atoms) => evalFailure(x0),
                (Closure fun) => evalFailure(x0)
                );
        }
    );   
    return result;
}


Atom apply(Atom atom, Atom[] arguments)
{
    auto closure = atom.toClosure();

    final switch (closure.type)
    {
        // this function is regular Scheme
        case Closure.Type.regular:
            // build new environment
            Atom[] paramList = toList(closure.params);
            Atom[string] values;

            if (paramList.length != arguments.length)
                throw new SchemeException(format("Expected %s arguments, got %s", paramList.length, arguments.length));

            for(size_t i = 0; i < paramList.length; ++i)
                values[cast(string)(paramList[i].toSymbol())] = arguments[i];

            Environment newEnv = new Environment(values, closure.env);
            return eval(closure.body_, newEnv);

        // this function is D code
        case Closure.Type.builtin:
            return closure.builtin(arguments);
    }
}
