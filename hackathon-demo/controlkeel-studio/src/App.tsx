import { useState, useRef, useEffect } from "react";
import { Send, Terminal, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { ScrollArea } from "@/components/ui/scroll-area";
import Markdown from "react-markdown";
import { motion } from "motion/react";

type Message = {
  role: "user" | "model";
  content: string;
  trace?: any[];
};

export default function App() {
  const [messages, setMessages] = useState<Message[]>([
    {
      role: "model",
      content: "🛡️ **ControlKeel Studio** initialized.\\nGovern your product, open-source repo, or AI agent workflow.\\n\\nPaste a GitHub URL, or ask me to build a governed feature.",
    },
  ]);
  const [input, setInput] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [messages]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;

    const userMessage: Message = { role: "user", content: input.trim() };
    setMessages((prev) => [...prev, userMessage]);
    setInput("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: [...messages, userMessage] }),
      });

      if (!response.ok) {
        throw new Error(`Failed to get response: ${response.status}`);
      }

      const data = await response.json();
      setMessages((prev) => [...prev, { role: "model", content: data.message, trace: data.trace }]);
    } catch (error) {
      console.error(error);
      setMessages((prev) => [
        ...prev,
        { role: "model", content: `🚫 GOVERNANCE: ERROR — Unable to connect to Mission Control. ${error instanceof Error ? error.message : ""}` },
      ]);
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      handleSubmit(e);
    }
  };

  return (
    <div className="flex h-screen w-full flex-col bg-[#0A0A0B] text-slate-300 font-sans overflow-hidden border border-white/10">
      <header className="h-14 border-b border-white/10 bg-[#0C0C0D] flex items-center justify-between px-4 sm:px-6 shrink-0">
        <div className="flex items-center gap-4">
          <div className="w-8 h-8 bg-blue-600 rounded flex items-center justify-center font-bold text-white text-xs tracking-tighter">CK</div>
          <h1 className="font-semibold tracking-tight text-slate-100">ControlKeel <span className="text-blue-500">Studio</span></h1>
          <span className="hidden sm:inline-block px-2 py-0.5 rounded border border-white/5 bg-white/5 text-[10px] text-slate-500 font-mono uppercase tracking-widest">Mission Control</span>
        </div>
        <div className="flex items-center gap-2 sm:gap-6 text-[11px] font-mono">
           <div className="flex flex-col items-end hidden sm:flex">
             <span className="text-slate-500 uppercase text-[9px]">Project ID</span>
             <span className="text-slate-300">ControlKeel Studio</span>
           </div>
           <div className="h-8 w-px bg-white/10 hidden sm:block"></div>
           <div className="flex flex-col items-end hidden sm:flex">
             <span className="text-slate-500 uppercase text-[9px]">Budget Remaining</span>
             <span className="text-blue-400">Live CK</span>
           </div>
           <div className="h-8 w-px bg-white/10 hidden sm:block"></div>
           <div className="flex items-center gap-1.5 border border-green-500/30 bg-green-500/10 px-2 py-1 rounded-full">
             <div className="h-2 w-2 rounded-full bg-green-500 animate-pulse"></div>
             <span className="text-green-500 font-bold tracking-widest uppercase">Live</span>
           </div>
        </div>
      </header>

      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <aside className="hidden md:flex w-64 flex-col border-r border-white/10 bg-[#0C0C0D] overflow-y-auto shrink-0">
          <div className="p-4 border-b border-white/10">
            <h2 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-3">Govern a project</h2>
            <div className="space-y-2">
              <button onClick={() => setInput("Govern this open source repo: https://github.com/langchain-ai/langchain")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">LangChain (AI agents)</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Fetch repo + risk analysis</div>
              </button>
              <button onClick={() => setInput("Govern this repo: https://github.com/vercel/next.js")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Next.js app</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Review Dockerfile, deps, config</div>
              </button>
              <button onClick={() => setInput("I want to govern my own project. Here is the tech stack: Node.js, Express, Postgres, deployed on AWS. What should I set up?")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">My own project</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Custom governance setup</div>
              </button>
            </div>
          </div>

          <div className="p-4 border-b border-white/10">
            <h2 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-3">Validate code</h2>
            <div className="space-y-2">
              <button onClick={() => setInput("Validate this code:\neval(user_input)")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Block RCE</div>
                <div className="text-[10px] text-slate-500 mt-0.5">eval/exec → BLOCK</div>
              </button>
              <button onClick={() => setInput("Validate this code:\napi_key = \"sk-proj-abc123def456\"")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Block secret leak</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Entropy detection</div>
              </button>
              <button onClick={() => setInput("Validate this shell:\nrm -rf /")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Block destructive shell</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Shell tripwires</div>
              </button>
              <button onClick={() => setInput("Validate this code:\ndef health_check():\n    return {\"status\": \"ok\"}")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Allow safe code</div>
                <div className="text-[10px] text-slate-500 mt-0.5">0 findings → ALLOW</div>
              </button>
            </div>
          </div>

          <div className="p-4 border-b border-white/10">
            <h2 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-3">Build & ship</h2>
            <div className="space-y-2">
              <button onClick={() => setInput("Build a user auth system with JWT tokens, email verification, and rate limiting. Create a governed implementation plan.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Build auth feature</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Governed plan + review gate</div>
              </button>
              <button onClick={() => setInput("I am ready to ship. Check budget, findings, and generate a proof bundle.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Ship readiness check</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Budget + proof + findings</div>
              </button>
              <button onClick={() => setInput("Remember: we decided to use JWT for auth, RSA-256 signing, 24h expiry, refresh token rotation.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Record decision</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Durable typed memory</div>
              </button>
            </div>
          </div>

          <div className="p-4 border-b border-white/10">
            <h2 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-3">Platform value</h2>
            <div className="space-y-2">
              <button onClick={() => setInput("Show me the full ControlKeel platform overview: governance, observability, policies, self-learning, benchmarks, integrations.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Full platform</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Everything CK controls</div>
              </button>
              <button onClick={() => setInput("Show observability, audit log, improvement loop, trends, and regressions.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Observability</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Audit + feedback loop</div>
              </button>
              <button onClick={() => setInput("Show policies, domain packs, compliance controls, and tool policy.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Policies</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Domain/compliance packs</div>
              </button>
              <button onClick={() => setInput("Show self-learning memory and prior decisions.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Self-learning</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Typed memory + recall</div>
              </button>
              <button onClick={() => setInput("Show benchmarks, evals, regressions, and policy promotion.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Benchmarks</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Evals + quality proof</div>
              </button>
              <button onClick={() => setInput("Show agent integrations, skills, providers, routing, and deploy surfaces.")} className="w-full text-left p-2 rounded-md border border-white/5 bg-white/[0.02] hover:bg-white/5 hover:border-blue-500/30 transition-colors">
                <div className="text-xs font-bold text-slate-200">Integrations</div>
                <div className="text-[10px] text-slate-500 mt-0.5">Hosts + deployment</div>
              </button>
            </div>
          </div>

          <div className="p-4 mt-auto">
            <h2 className="text-[10px] font-bold text-slate-500 uppercase tracking-widest mb-3">Links</h2>
            <div className="space-y-2">
              <a href="https://controlkeel-834811228927.us-central1.run.app/missions/1" target="_blank" rel="noreferrer" className="flex items-center gap-2 text-xs text-blue-400 hover:text-blue-300 hover:underline p-1.5 rounded bg-blue-500/5 border border-blue-500/10 transition-colors">
                <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div>
                Mission Control
              </a>
              <a href="https://controlkeel-834811228927.us-central1.run.app/findings" target="_blank" rel="noreferrer" className="flex items-center gap-2 text-xs text-blue-400 hover:text-blue-300 hover:underline p-1.5 rounded bg-blue-500/5 border border-blue-500/10 transition-colors">
                <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div>
                Findings
              </a>
              <a href="https://controlkeel-834811228927.us-central1.run.app/proofs" target="_blank" rel="noreferrer" className="flex items-center gap-2 text-xs text-blue-400 hover:text-blue-300 hover:underline p-1.5 rounded bg-blue-500/5 border border-blue-500/10 transition-colors">
                <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div>
                Proof Bundles
              </a>
              <a href="https://controlkeel-834811228927.us-central1.run.app/benchmarks" target="_blank" rel="noreferrer" className="flex items-center gap-2 text-xs text-blue-400 hover:text-blue-300 hover:underline p-1.5 rounded bg-blue-500/5 border border-blue-500/10 transition-colors">
                <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div>
                Benchmarks
              </a>
              <a href="https://controlkeel-834811228927.us-central1.run.app/ship" target="_blank" rel="noreferrer" className="flex items-center gap-2 text-xs text-blue-400 hover:text-blue-300 hover:underline p-1.5 rounded bg-blue-500/5 border border-blue-500/10 transition-colors">
                <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div>
                Ship Readiness
              </a>
            </div>
          </div>
        </aside>

        <div className="flex-1 flex flex-col min-w-0">
          <ScrollArea className="flex-1 p-4" ref={scrollRef}>
            <div className="mx-auto max-w-4xl space-y-6 pb-20">
              {messages.length === 1 && (
                <div className="text-center py-10">
                  <h2 className="text-xl font-semibold mb-2 bg-gradient-to-r from-white via-indigo-300 to-blue-400 bg-clip-text text-transparent">Govern any agent workflow.</h2>
                  <p className="text-sm text-slate-500 max-w-md mx-auto">
                    Paste a GitHub URL, code snippet, shell command, config, or PR diff.
                    ControlKeel validates it, creates findings, opens review gates, tracks budget,
                    observes the workflow, learns durable memory, applies policy packs,
                    benchmarks quality, and generates proof bundles — all in real time.
                  </p>
                </div>
              )}
              {messages.filter((m, i) => i !== 0).map((m, i) => (
            <motion.div
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              key={i}
              className={`flex flex-col gap-2 ${
                m.role === "user" ? "items-end" : "items-start"
              }`}
            >
              <div
                className={`flex max-w-[85%] flex-col rounded px-5 py-4 ${
                  m.role === "user"
                    ? "bg-blue-600/10 border border-blue-600/30 text-blue-100 shadow-sm"
                    : "bg-[#0C0C0D] border border-white/10 text-slate-300 shadow-sm"
                }`}
              >
                <div className="flex items-center gap-2 mb-2 text-[10px] font-bold uppercase tracking-widest text-slate-500">
                  {m.role === "user" ? (
                    <>
                      <span>USER</span>
                    </>
                  ) : (
                    <>
                      <div className="w-4 h-4 bg-blue-600 rounded-[2px] flex items-center justify-center font-bold text-white text-[8px] tracking-tighter">CK</div>
                      <span className="text-blue-400">ControlKeel</span>
                    </>
                  )}
                </div>
                <div className="text-xs font-mono leading-relaxed text-slate-300 space-y-4 [&_p]:whitespace-pre-wrap [&_pre]:bg-[#0C0C0D] [&_pre]:p-3 [&_pre]:rounded [&_pre]:overflow-x-auto [&_pre]:border [&_pre]:border-white/10 [&_:not(pre)>code]:bg-white/5 [&_:not(pre)>code]:text-blue-300 [&_:not(pre)>code]:px-1.5 [&_:not(pre)>code]:py-0.5 [&_:not(pre)>code]:rounded-sm [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5 [&_h1]:text-sm [&_h1]:font-sans [&_h1]:font-bold [&_h1]:text-slate-100 [&_h2]:text-xs [&_h2]:font-sans [&_h2]:font-bold [&_h2]:text-slate-100 [&_h3]:text-xs [&_h3]:font-sans [&_h3]:font-bold [&_h3]:text-slate-100 [&_blockquote]:border-l-4 [&_blockquote]:border-white/20 [&_blockquote]:pl-4 [&_blockquote]:italic [&_blockquote]:text-slate-400">
                  <Markdown>{m.content}</Markdown>
                </div>
                {m.trace && m.trace.length > 0 && (
                  <div className="mt-4 pt-3 border-t border-dashed border-white/10 flex flex-col gap-1.5">
                    {m.trace.map((t, idx) => {
                      const decision = t.result?.decision;
                      let badge = null;
                      if (decision === "block") badge = <span className="inline-flex items-center text-[9px] font-bold px-1.5 py-0.5 rounded mr-1.5 bg-red-500/15 text-red-500">BLOCK</span>;
                      if (decision === "warn") badge = <span className="inline-flex items-center text-[9px] font-bold px-1.5 py-0.5 rounded mr-1.5 bg-yellow-500/15 text-yellow-500">WARN</span>;
                      if (decision === "allow") badge = <span className="inline-flex items-center text-[9px] font-bold px-1.5 py-0.5 rounded mr-1.5 bg-green-500/15 text-green-500">ALLOW</span>;
                      
                      return (
                        <div key={idx} className="font-mono text-[10px] text-slate-500 px-2 py-1.5 bg-[#0A0C12] rounded border border-white/5">
                          {badge}
                          <strong className="text-slate-400">{t.tool}</strong>
                          ({JSON.stringify(t.args || {}).slice(0, 120)})
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            </motion.div>
          ))}
          {isLoading && (
            <motion.div 
               initial={{ opacity: 0, scale: 0.95 }}
               animate={{ opacity: 1, scale: 1 }}
               className="flex max-w-[85%] flex-col rounded bg-[#0C0C0D] border border-white/10 px-5 py-4 text-slate-400 shadow-sm"
            >
               <div className="flex items-center gap-2 mb-2 text-[10px] font-bold uppercase tracking-widest text-slate-500">
                  <div className="w-4 h-4 bg-blue-600 rounded-[2px] flex items-center justify-center font-bold text-white text-[8px] tracking-tighter">CK</div>
                  <span className="text-blue-400">ControlKeel</span>
                </div>
              <div className="flex items-center gap-1.5 pt-1 pb-1">
                <div className="h-2 w-2 rounded-full bg-blue-500 animate-pulse"></div>
                <div className="h-2 w-2 rounded-full bg-blue-500 animate-pulse delay-75"></div>
                <div className="h-2 w-2 rounded-full bg-blue-500 animate-pulse delay-150"></div>
              </div>
            </motion.div>
          )}
        </div>
      </ScrollArea>

      <div className="border-t border-white/10 bg-[#0C0C0D] p-4 flex-shrink-0">
        <div className="mx-auto max-w-4xl">
          <form
            onSubmit={handleSubmit}
            className="flex items-end gap-2 rounded border border-white/10 bg-[#0A0A0B] p-2 focus-within:border-blue-500/50 transition-colors"
          >
            <div className="flex items-center px-2 pb-2">
               <span className="text-xs font-mono text-blue-500 font-bold">$</span>
            </div>
            <Textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="ck_validate('code', 'code')"
              className="max-h-32 min-h-[40px] flex-1 resize-none border-0 bg-transparent shadow-none focus-visible:ring-0 focus-visible:ring-offset-0 text-slate-300 font-mono text-xs py-2"
              rows={1}
            />
            <Button
              type="submit"
              size="icon"
              disabled={!input.trim() || isLoading}
              className="h-8 w-8 shrink-0 rounded bg-blue-600 text-white hover:bg-blue-500 disabled:opacity-50 disabled:bg-slate-800 disabled:text-slate-500 transition-colors"
            >
              <Send className="h-3 w-3" />
            </Button>
          </form>

          <div className="mt-3 flex items-center justify-between text-[10px] font-mono text-slate-600">
             <div className="flex items-center gap-3">
               <div className="flex items-center gap-1.5">
                 <div className="w-1.5 h-1.5 rounded-full bg-green-500"></div>
                 <span className="uppercase">Executor Active</span>
               </div>
               <div className="flex items-center gap-1.5 hidden sm:flex">
                 <div className="w-1.5 h-1.5 rounded-full bg-slate-600"></div>
                 <span className="uppercase">Scanner: Deterministic</span>
               </div>
             </div>
             <span className="text-blue-500/80 uppercase">GOVERNANCE MODE: RESTRICTIVE</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>
  );
}
